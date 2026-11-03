"""Validate root service installation boundaries without running privileged commands."""
from pathlib import Path
import plistlib

base = Path(__file__).resolve().parents[1] / "producerprobe/layout"
service = plistlib.loads((base / "Library/LaunchDaemons/com.idonamaan.ieb.process-reader.plist").read_bytes())
assert service["UserName"] == "root"
assert service["ProgramArguments"] == ["/var/jb/usr/libexec/ieb-process-reader"]
assert service["MachServices"] == {"com.idonamaan.ieb.process-reader": True}
assert service["RunAtLoad"] is False and service["KeepAlive"] is False
assert service["EnableTransactions"] is True and service["EnablePressuredExit"] is True
for name in ("postinst", "prerm"):
    path = base / "DEBIAN" / name
    script = path.read_text()
    assert "set -eu" in script and "/var/jb/usr/bin/launchctl" in script
    assert not any(line.lstrip().startswith(("if /bin/launchctl", "/bin/launchctl")) for line in script.splitlines())
    assert not any(word in script for word in ("sudo", "passwd", "chmod 4", "curl", "wget"))
    assert path.stat().st_mode & 0o777 == 0o755
assert "--check-service" in (base / "DEBIAN/postinst").read_text()
print("PASS on-demand root launchd layout and fixed install lifecycle")
