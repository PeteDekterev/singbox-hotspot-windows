# VPN и Wi-Fi hotspot

Эта папка настраивает последовательность: **sing-box VPN → адаптер `tun0` → раздача Wi-Fi `DektHotspot`**.

Hiddify для этой схемы больше не запускается и не нужен. Автозапуск использует только `sing-box.exe` и автономный конфигурационный файл в `%LOCALAPPDATA%\PortableGit-hotspot\sing-box.json`.

## Обычное использование

### После входа в Windows

Задача Планировщика `sing-box VPN + Hotspot` запускается при входе пользователя. Она:

1. Останавливает Hiddify, если он был запущен, чтобы два клиента не заняли один TUN-адаптер.
2. Запускает `sing-box` с VLESS Reality-конфигурацией.
3. Ждёт, пока `tun0` получит доступ в интернет.
4. Включает Wi-Fi `DektHotspot` и ICS через `tun0`.

Обычно это занимает около 20–40 секунд после входа в Windows.

### Запустить вручную

Запустите двойным щелчком [start-singbox-hotspot.cmd](start-singbox-hotspot.cmd). Он запускает ту же последовательность, что и задача автозапуска.

### Проверить состояние

Запустите двойным щелчком [status-hotspot.cmd](status-hotspot.cmd). Он показывает состояние Wi-Fi, virtual hosted adapter и Internet Connection Sharing (ICS).

### Остановить Wi-Fi раздачу

Запустите двойным щелчком [stop-hotspot.cmd](stop-hotspot.cmd). Он выключает ICS и SSID, но не останавливает sing-box VPN.

## Скрипты

| Файл | Назначение |
| --- | --- |
| [start-singbox-hotspot.ps1](start-singbox-hotspot.ps1) | Основной скрипт: direct sing-box, проверка `tun0`, запуск hotspot. |
| [start-singbox-hotspot.cmd](start-singbox-hotspot.cmd) | Удобный ручной запуск основного скрипта. |
| [install-singbox-hotspot-autostart.ps1](install-singbox-hotspot-autostart.ps1) | Создаёт/обновляет задачу `sing-box VPN + Hotspot` и удаляет старую задачу Hiddify. |
| [hotspot-start.ps1](hotspot-start.ps1) | Запускает hosted network и ICS. Автоматически освобождает устаревший адрес `192.168.137.1` только с отключённого адаптера. |
| [hotspot-stop.ps1](hotspot-stop.ps1) | Выключает ICS и hosted network. |
| [hotspot-status.ps1](hotspot-status.ps1) | Диагностика Wi-Fi, IP-адреса виртуального адаптера и ICS. |
| [vpn-hotspot-startup.log](vpn-hotspot-startup.log) | Журнал запусков VPN/hotspot. Смотреть его при проблемах. |

## Устаревшие скрипты Hiddify

Старые скрипты перенесены в [deprecated](deprecated/). Они сохранены только для истории и **не должны запускаться**:

- [deprecated/start-vpn-hotspot.ps1](deprecated/start-vpn-hotspot.ps1)
- [deprecated/install-vpn-hotspot-autostart.ps1](deprecated/install-vpn-hotspot-autostart.ps1)

Они запускают Hiddify и не являются частью текущего автозапуска.

## Что считать успешным запуском

В журнале должны появиться строки:

```text
Direct sing-box tunnel is ready.
Hotspot started successfully through direct sing-box.
```

В `status-hotspot.cmd` источник ICS должен быть `tun0`, а virtual hosted adapter — иметь IPv4-адрес `192.168.137.1`.

## Если Wi-Fi видно, но к нему не подключаются

1. Запустите `stop-hotspot.cmd`.
2. Запустите `start-singbox-hotspot.cmd` от имени администратора.
3. Откройте `vpn-hotspot-startup.log` и посмотрите последнюю строку с `ERROR`.

Не назначайте `192.168.137.1` вручную: этот адрес и DHCP должен выдавать ICS.

## Безопасность

`%LOCALAPPDATA%\PortableGit-hotspot\sing-box.json` содержит параметры VPN, включая секретные ключи/идентификаторы. Не публикуйте этот файл, не отправляйте его в чат и не добавляйте в Git.
