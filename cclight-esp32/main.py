"""cclight-esp32: USB serial LED controller for ESP32-C3 (MicroPython).

Runs on boot as main.py. Listens on the native USB CDC serial port for
line-based commands from the Mac agent and drives an external LED.

Protocol (one command per line, case-insensitive):
    LED ON   -> OK ON
    LED OFF  -> OK OFF
    STATUS   -> OK ON | OK OFF
    PING     -> PONG
    anything else -> ERR unknown command
"""

import select
import sys

from machine import Pin

# ---- hardware config: adjust to your wiring ----
LED_PIN = 4        # GPIO the external LED is wired to
ACTIVE_HIGH = True  # True: high level lights the LED; False: low level


class Led:
    def __init__(self, pin_no, active_high):
        self._pin = Pin(pin_no, Pin.OUT)
        self._active_high = active_high
        self._is_on = False
        self.off()

    def on(self):
        self._pin.value(1 if self._active_high else 0)
        self._is_on = True

    def off(self):
        self._pin.value(0 if self._active_high else 1)
        self._is_on = False

    @property
    def is_on(self):
        return self._is_on


def handle_command(line, led):
    """Return the reply string for one command line."""
    cmd = " ".join(line.split()).upper()
    if cmd == "LED ON":
        led.on()
        return "OK ON"
    if cmd == "LED OFF":
        led.off()
        return "OK OFF"
    if cmd == "STATUS":
        return "OK ON" if led.is_on else "OK OFF"
    if cmd == "PING":
        return "PONG"
    return "ERR unknown command"


def main():
    led = Led(LED_PIN, ACTIVE_HIGH)
    poller = select.poll()
    poller.register(sys.stdin, select.POLLIN)

    while True:
        try:
            if not poller.poll(100):
                continue
            line = sys.stdin.readline()
            if line is None:
                continue
            line = line.strip()
            if not line:
                continue
            print(handle_command(line, led))
        except KeyboardInterrupt:
            raise
        except Exception as exc:
            print("ERR %s" % exc)


main()
