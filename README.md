# Пульт

Управление ПК с iPhone: экран, файлы, приложения, тачпад.

## Онлайн через Tailscale

1. Поставь [Tailscale](https://tailscale.com/download) на **ПК** и **iPhone**. Один аккаунт.
2. Оба устройства включены в Tailscale (зелёный статус).
3. На ПК: `pip install -r Agent/requirements.txt` и `python Agent/pult_agent.py`.
4. В окне агента берёшь **Tailscale** (`100.x.x.x`) и **PIN**.
5. На iPhone: **+ → Tailscale** → вставь `100.x.x.x` или `имя.ts.net` → PIN.

Проброс порта на роутере не нужен. Трафик идёт через сеть Tailscale.

Дома в одной Wi-Fi можно без Tailscale: **+ → Wi-Fi → LAN IP**.

## Сборка

Xcode 15+, iOS 17+. GitHub Action кладёт unsigned `Pult.ipa`.
