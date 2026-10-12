# SHUN HUB releases

The public home of [SHUN HUB](https://github.com/shuniverse-dev/shun-hub), the Shuniverse launch station:
the Hub's own releases (Python wheels), `hub.json` (which version is current), the public app catalog
(`catalogs/public.json`) and the one-line installer for Windows.

Install or repair the Hub on a Windows computer: open PowerShell and paste

    irm https://raw.githubusercontent.com/shuniverse-dev/shun-releases/main/install.ps1 | iex

The installer fetches uv, lets it install Python 3.13 and the Hub, adds a Start Menu entry "SHUN HUB" and starts
the Hub. Private apps are not listed here; they are unlocked inside the Hub with a key and a GitHub token.
