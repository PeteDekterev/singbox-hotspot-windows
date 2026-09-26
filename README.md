# VPN и Wi-Fi hotspot

Эта папка настраивает последовательность: **TrustTunnel VPN → адаптер `tun0` → раздача Wi-Fi `DektHotspot`**.

Старый sing-box (VLESS Reality на заблокированный сервер 195.63.163.172) больше не запускается и не нужен. Его скрипты перенесены в [deprecated](deprecated/), а сам `sing-box-1.14.0/` можно удалить. Автозапуск использует только `trusttunnel-client\trusttunnel_client.exe` и автономный конфигурационный файл в `%LOCALAPPDATA%\PortableGit-hotspot\trusttunnel_client.toml`.

## Обычное использование

### После входа в Windows

Задача Планировщика `TrustTunnel VPN + Hotspot` запускается при входе пользователя. Она:

1. Останавливает Hiddify и sing-box, если они были запущены, чтобы никто не занял TUN-адаптер.
2. Запускает `trusttunnel_client` с конфигурацией TrustTunnel (сервер `feel.cloud-ip.cc` / `79.143.29.74:443`).
3. Ждёт, пока `tun0` получит доступ в интернет.
4. Включает Wi-Fi `DektHotspot` и ICS через `tun0`.

Обычно это занимает около 20–40 секунд после входа в Windows.

### Запустить вручную

Запустите двойным щелчком [start-trusttunnel-hotspot.cmd](start-trusttunnel-hotspot.cmd). Он запускает ту же последовательность, что и задача автозапуска.

### Проверить состояние

Запустите двойным щелчком [status-hotspot.cmd](status-hotspot.cmd). Он показывает состояние Wi-Fi, virtual hosted adapter и Internet Connection Sharing (ICS).

### Остановить Wi-Fi раздачу

Запустите двойным щелчком [stop-hotspot.cmd](stop-hotspot.cmd). Он выключает ICS и SSID, но не останавливает TrustTunnel VPN (как и раньше с sing-box).

## Скрипты

| Файл | Назначение |
| --- | --- |
| [start-trusttunnel-hotspot.ps1](start-trusttunnel-hotspot.ps1) | Основной скрипт: запуск TrustTunnel-клиента, проверка `tun0`, запуск hotspot. |
| [start-trusttunnel-hotspot.cmd](start-trusttunnel-hotspot.cmd) | Удобный ручной запуск основного скрипта. |
| [install-trusttunnel-hotspot-autostart.ps1](install-trusttunnel-hotspot-autostart.ps1) | Создаёт/обновляет задачу `TrustTunnel VPN + Hotspot` и удаляет старые задачи Hiddify и sing-box. |
| [hotspot-start.ps1](hotspot-start.ps1) | Запускает hosted network и ICS. Автоматически освобождает устаревший адрес `192.168.137.1` только с отключённого адаптера. |
| [hotspot-stop.ps1](hotspot-stop.ps1) | Выключает ICS и hosted network. |
| [hotspot-status.ps1](hotspot-status.ps1) | Диагностика Wi-Fi, IP-адреса виртуального адаптера и ICS. |
| `trusttunnel-client\` | TrustTunnel CLI Client 1.1.7 (`trusttunnel_client.exe` + `wintun.dll` + `setup_wizard.exe`). Не коммитится в Git. |
| [vpn-hotspot-startup.log](vpn-hotspot-startup.log) | Журнал запусков VPN/hotspot. Смотреть его при проблемах. |

## Устаревшие скрипты

Старые скрипты перенесены в [deprecated](deprecated/). Они сохранены только для истории и **не должны запускаться**:

- [deprecated/start-vpn-hotspot.ps1](deprecated/start-vpn-hotspot.ps1)
- [deprecated/install-vpn-hotspot-autostart.ps1](deprecated/install-vpn-hotspot-autostart.ps1)
- [deprecated/start-singbox-hotspot.ps1](deprecated/start-singbox-hotspot.ps1)
- [deprecated/start-singbox-hotspot.cmd](deprecated/start-singbox-hotspot.cmd)
- [deprecated/install-singbox-hotspot-autostart.ps1](deprecated/install-singbox-hotspot-autostart.ps1)

Они запускают Hiddify или sing-box и не являются частью текущего автозапуска.

## Что считать успешным запуском

В журнале должны появиться строки:

```text
TrustTunnel tunnel is ready.
Hotspot started successfully through TrustTunnel.
```

В `status-hotspot.cmd` источник ICS должен быть `tun0`, а virtual hosted adapter — иметь IPv4-адрес `192.168.137.1`.

## Ограничения текущего VPN-сервера

Сервер `79.143.29.74` находится в Москве (Selectel), поэтому:

- ChatGPT/OpenAI отдают HTTP 403 (гео-блок RU) — лечится только нероссийским сервером.
- Подсети дата-центров Telegram у Selectel закрыты (достижим 1 IP из 7) — Telegram через раздачу может не работать.

Протокол TrustTunnel маскируется под HTTPS и обходит ТСПУ; Gemini и остальной заблокированный web работают.

## Если Wi-Fi видно, но к нему не подключаются

1. Запустите `stop-hotspot.cmd`.
2. Запустите `start-trusttunnel-hotspot.cmd` от имени администратора.
3. Откройте `vpn-hotspot-startup.log` и посмотрите последнюю строку с `ERROR`. Диагностика самого VPN-клиента — в `%LOCALAPPDATA%\PortableGit-hotspot\trusttunnel-client.err.log`.

Не назначайте `192.168.137.1` вручную: этот адрес и DHCP должен выдавать ICS.

## Безопасность

`%LOCALAPPDATA%\PortableGit-hotspot\trusttunnel_client.toml` содержит параметры VPN, включая логин/пароль туннеля. Не публикуйте этот файл, не отправляйте его в чат и не добавляйте в Git. То же правило, что и раньше было для `sing-box.json`.

Клиент запускается только с TUN-listener'ом: CLI-клиент принимает один тип listener'а за раз, а TUN нужен цепочке. Весь трафик самого ПК при этом тоже идёт через туннель (`vpn_mode = "general"`), отдельный SOCKS5-прокси на ПК не поднят.
