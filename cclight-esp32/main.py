"""cclight-esp32: USB serial LED controller for ESP32-C3 (MicroPython).

Runs on boot as main.py. Listens on the native USB CDC serial port for
line-based commands from the Mac agent and drives an external LED with
one of several patterns (state language v2).

Protocol (one command per line, case-insensitive):
    LED BREATH  -> OK BREATH   breathing, ~3s cycle (Claude is working)
    LED FLASH   -> OK FLASH    5 Hz blink (permission request)
    LED DOUBLE  -> OK DOUBLE   double-blink + pause (error / test failure)
    LED OFF     -> OK OFF      off (turn finished, waiting for user)
    LED ON      -> OK ON       steady on (hardware debugging only)
    STATUS      -> OK <mode>
    PING        -> PONG
    anything else -> ERR unknown command
"""

import select
import sys
import time

from machine import Pin, PWM

# ---- hardware config: adjust to your wiring ----
LED_PIN = 4         # GPIO the external LED is wired to
ACTIVE_HIGH = True  # True: high level lights the LED; False: low level

TICK_MS = 20            # pattern refresh / serial poll interval
BREATH_PERIOD_MS = 3000
FLASH_PERIOD_MS = 200   # 5 Hz
DOUBLE_PERIOD_MS = 1200  # two 100ms flashes, then pause

PWM_MAX = 1023


class Led:
    """PWM-driven LED with time-based patterns; call tick() every TICK_MS."""

    MODES = ("BREATH", "FLASH", "DOUBLE", "ON", "OFF")

    def __init__(self, pin_no, active_high):
        self._pwm = PWM(Pin(pin_no), freq=1000)
        self._active_high = active_high
        self._mode = "OFF"
        self._t0 = time.ticks_ms()
        self._level(0)

    def _level(self, duty):
        """duty 0..PWM_MAX where PWM_MAX = full brightness."""
        if not self._active_high:
            duty = PWM_MAX - duty
        self._pwm.duty(duty)

    def set_mode(self, mode):
        if mode == self._mode:
            return  # idempotent: a repeated command must not restart the phase
        self._mode = mode
        self._t0 = time.ticks_ms()
        self.tick()

    @property
    def mode(self):
        return self._mode

    def tick(self):
        t = time.ticks_diff(time.ticks_ms(), self._t0)
        if self._mode == "ON":
            self._level(PWM_MAX)
        elif self._mode == "OFF":
            self._level(0)
        elif self._mode == "BREATH":
            # triangle wave: 0 -> max -> 0 over BREATH_PERIOD_MS
            phase = t % BREATH_PERIOD_MS
            half = BREATH_PERIOD_MS // 2
            duty = phase if phase < half else BREATH_PERIOD_MS - phase
            self._level(duty * PWM_MAX // half)
        elif self._mode == "FLASH":
            phase = t % FLASH_PERIOD_MS
            self._level(PWM_MAX if phase < FLASH_PERIOD_MS // 2 else 0)
        elif self._mode == "DOUBLE":
            # on 0-100ms, off 100-200, on 200-300, then off until 1200
            phase = t % DOUBLE_PERIOD_MS
            on = phase < 100 or 200 <= phase < 300
            self._level(PWM_MAX if on else 0)


def handle_command(line, led):
    """Return the reply string for one command line."""
    parts = line.split()
    cmd = " ".join(parts).upper()
    if cmd == "PING":
        return "PONG"
    if cmd == "STATUS":
        return "OK %s" % led.mode
    if len(parts) == 2 and parts[0].upper() == "LED":
        mode = parts[1].upper()
        if mode in Led.MODES:
            led.set_mode(mode)
            return "OK %s" % mode
    return "ERR unknown command"


def main():
    led = Led(LED_PIN, ACTIVE_HIGH)
    poller = select.poll()
    poller.register(sys.stdin, select.POLLIN)

    while True:
        try:
            if poller.poll(TICK_MS):
                line = sys.stdin.readline()
                if line is not None:
                    line = line.strip()
                    if line:
                        print(handle_command(line, led))
            led.tick()
        except KeyboardInterrupt:
            raise
        except Exception as exc:
            print("ERR %s" % exc)


main()
