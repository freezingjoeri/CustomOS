# CustomOS
dit in mijn Ubuntu Os



To instal use:

sudo apt update && sudo apt install -y git
git clone [https://github.com/<jouw-user>/CustomOS.git](https://github.com/freezingjoeri/CustomOS)
cd CustomOS
sudo bash install.sh

Commants:

Status checken
sudo customos --status

Naar Desktop‑mode (GUI aan: XFCE + LightDM)
sudo customos --desktop
Daarna:
Wacht een paar seconden.
Ga naar de grafische sessie met Ctrl + Alt + F1 t/m F7 (meestal F1 of F2).

Naar Server‑mode (GUI uit, alleen services)
sudo customos --server
Dit:
Stopt de display manager / X (LightDM).
Laat Docker + (Jellyfin/Plex/Samba, als geïnstalleerd) doorlopen.

Eenmalige health‑check, leesbare tekst
guardian --check

Raw metrics als JSON (voor bv. jq)
guardian --json

Als background watcher (doet systemd al, maar handmatig kan ook)
guardian --watch

first
cd /home/user/CustomOS
ls
User for own name

then
cd CustomOS        # naar de binnenste CustomOS-map
ls  

voor nu instaleer eerst: sudo apt install dos2unix

en dan: sudo apt install -y dos2unix
dos2unix install.sh
sudo bash install.sh

instaleer eerst alles wat hier boven staat en dan de nieuwe {dit is tijdelijk totdat het gefixt is}
