import serial, time, sys
try:
    s = serial.Serial("COM13", 115200, timeout=0.3)
except Exception as e:
    print("OPEN FAILED:", e); sys.exit(1)
print("opened COM13 @115200, cts", s.cts, "dsr", s.dsr)
s.reset_input_buffer()
for cmd in (b"F500\r\n", b"F440\r\n"):
    s.write(cmd); s.flush()
    time.sleep(0.4)
    data = s.read(64)
    print(cmd, "->", data)
s.close()
