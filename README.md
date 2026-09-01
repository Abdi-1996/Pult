# Пульт

Управление компьютером с iPhone: живой экран, файлы, приложения, тачпад.

Репозиторий: https://github.com/Abdi-1996/Pult

## Что внутри

- `Pult.xcodeproj` — приложение для iPhone / iPad
- `Pult/` — SwiftUI
- `Agent/pult_agent.py` — агент на Windows / macOS / Linux

## 1. Компьютер

```bash
git clone https://github.com/Abdi-1996/Pult.git
cd Pult
pip install -r Agent/requirements.txt
python Agent/pult_agent.py
```

В консоли появятся PIN и IP.

## 2. iPhone

Нужен Mac с Xcode 15+.

```bash
git clone https://github.com/Abdi-1996/Pult.git
open Pult/Pult.xcodeproj
```

Signing & Capabilities → свой Apple ID → подключи iPhone кабелем → Run.

В приложении: **+** → IP агента → PIN.

Телефон и ПК — одна Wi-Fi, не гостевая.

## Вкладки

| Экран | Зачем |
|---|---|
| Экран | Картинка ПК + управление пальцем |
| Файлы | Скачать на iPhone / залить на ПК |
| Приложения | Запуск программ ПК |
| Пульт | Тачпад и клавиатура |

Иконку в Xcode можно поставить свою: `Pult/Assets.xcassets/AppIcon.appiconset/AppIcon.png` 1024×1024.
