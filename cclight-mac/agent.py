"""cclight-mac: HTTP agent exposing the cclight-esp32 chip over USB serial.

Endpoints (all synchronous — each waits for the chip's reply):
    POST /led/<mode>  -> {"ok": true, "reply": "OK <MODE>"}
                         mode: breath (working) | flash (permission request)
                             | double (error) | off (idle, waiting for user)
                             | on (steady, debugging)
    GET  /led         -> {"ok": true, "mode": "breath"|"flash"|"double"|"on"|"off"}
    GET  /health      -> {"connected": bool, "port": str|null}

The serial link is managed by ChipConnection: it auto-discovers the chip
(PING/PONG handshake), heartbeats it in the background, and reconnects
automatically after any failure or USB unplug.
"""

import glob
import logging
import os
import threading

import serial
from flask import Flask, jsonify, request

BAUD = 115200
CMD_TIMEOUT = 2.0          # seconds to wait for a chip reply
HEARTBEAT_INTERVAL = 5.0   # seconds between background PINGs
RECONNECT_INTERVAL = 3.0   # seconds between reconnect scans
PORT_GLOB = "/dev/tty.usbmodem*"  # overridden by CCLIGHT_PORT env var

log = logging.getLogger("cclight")


class ChipDisconnected(Exception):
    pass


class ChipTimeout(Exception):
    pass


class ChipConnection:
    """Owns the serial port; thread-safe synchronous commands + auto-reconnect."""

    def __init__(self, heartbeat_interval=HEARTBEAT_INTERVAL,
                 reconnect_interval=RECONNECT_INTERVAL):
        self._lock = threading.RLock()
        self._serial = None
        self._port = None
        self._heartbeat_interval = heartbeat_interval
        self._reconnect_interval = reconnect_interval
        self._stop = threading.Event()
        self._thread = threading.Thread(target=self._supervisor, daemon=True)

    # ---- public API ----

    def start(self):
        self._connect()
        self._thread.start()

    def stop(self):
        self._stop.set()
        self._thread.join(timeout=5)
        self._close("shutdown")

    @property
    def connected(self):
        with self._lock:
            return self._serial is not None

    @property
    def port(self):
        with self._lock:
            return self._port

    def send_command(self, cmd):
        """Send one command line, wait for one reply line. Synchronous."""
        with self._lock:
            if self._serial is None:
                raise ChipDisconnected()
            try:
                log.info("-> chip: %s", cmd)
                self._serial.reset_input_buffer()
                self._serial.write((cmd + "\r\n").encode())
                self._serial.flush()
                reply = self._serial.readline().decode(errors="replace").strip()
            except (serial.SerialException, OSError) as exc:
                log.error("serial error during %r: %s — dropping connection", cmd, exc)
                self._close("serial error")
                raise ChipDisconnected() from exc
            if not reply:
                log.error("timeout waiting for reply to %r — dropping connection", cmd)
                self._close("reply timeout")
                raise ChipTimeout()
            log.info("<- chip: %s", reply)
            return reply

    # ---- connection management ----

    def _candidate_ports(self):
        env_port = os.environ.get("CCLIGHT_PORT")
        if env_port:
            return [env_port]
        return sorted(glob.glob(PORT_GLOB))

    def _connect(self):
        candidates = self._candidate_ports()
        if not candidates:
            log.warning("no serial ports matching %s", PORT_GLOB)
            return False
        log.info("scanning ports: %s", ", ".join(candidates))
        for port in candidates:
            try:
                ser = serial.Serial(port, BAUD, timeout=CMD_TIMEOUT)
            except (serial.SerialException, OSError) as exc:
                log.warning("cannot open %s: %s", port, exc)
                continue
            try:
                ser.reset_input_buffer()
                ser.write(b"PING\r\n")
                ser.flush()
                reply = ser.readline().decode(errors="replace").strip()
            except (serial.SerialException, OSError) as exc:
                log.warning("probe failed on %s: %s", port, exc)
                ser.close()
                continue
            if reply == "PONG":
                with self._lock:
                    self._serial = ser
                    self._port = port
                log.info("chip connected on %s", port)
                return True
            log.warning("%s replied %r, not our chip", port, reply)
            ser.close()
        return False

    def _close(self, reason):
        with self._lock:
            if self._serial is not None:
                log.warning("chip disconnected (%s), was on %s", reason, self._port)
                try:
                    self._serial.close()
                except (serial.SerialException, OSError):
                    pass
                self._serial = None
                self._port = None

    def _supervisor(self):
        """Background loop: heartbeat while connected, reconnect while not."""
        while not self._stop.is_set():
            if self.connected:
                self._stop.wait(self._heartbeat_interval)
                if self._stop.is_set():
                    return
                try:
                    self.send_command("PING")
                except (ChipDisconnected, ChipTimeout):
                    pass  # already logged and closed; next loop reconnects
            else:
                log.info("reconnecting...")
                if not self._connect():
                    self._stop.wait(self._reconnect_interval)


# ---- HTTP layer ----

def create_app(chip):
    app = Flask("cclight-mac")

    def run_command(cmd):
        """Returns (reply, None) on success or (None, error_response) on failure."""
        try:
            reply = chip.send_command(cmd)
        except ChipDisconnected:
            return None, (jsonify({"ok": False, "error": "chip disconnected"}), 503)
        except ChipTimeout:
            return None, (jsonify({"ok": False, "error": "chip timeout"}), 504)
        if reply.startswith("ERR"):
            return None, (jsonify({"ok": False, "error": reply}), 502)
        return reply, None

    @app.before_request
    def log_request():
        log.info("http %s %s", request.method, request.path)

    MODES = ("breath", "flash", "double", "on", "off")

    @app.post("/led/<mode>")
    def led_set(mode):
        if mode not in MODES:
            return jsonify({"ok": False,
                            "error": "unknown mode, use one of: %s" % ", ".join(MODES)}), 404
        reply, err = run_command("LED " + mode.upper())
        if err:
            return err
        return jsonify({"ok": True, "reply": reply})

    @app.get("/led")
    def led_status():
        reply, err = run_command("STATUS")
        if err:
            return err
        return jsonify({"ok": True, "mode": reply.split()[-1].lower()})

    @app.get("/health")
    def health():
        return jsonify({"connected": chip.connected, "port": chip.port})

    return app


def main():
    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s %(levelname)s %(message)s",
    )
    host = os.environ.get("CCLIGHT_HOST", "127.0.0.1")
    http_port = int(os.environ.get("CCLIGHT_HTTP_PORT", "8123"))

    chip = ChipConnection()
    log.info("starting cclight-mac agent")
    chip.start()
    app = create_app(chip)
    log.info("http server listening on %s:%d", host, http_port)
    try:
        app.run(host=host, port=http_port, threaded=True)
    finally:
        chip.stop()


if __name__ == "__main__":
    main()
