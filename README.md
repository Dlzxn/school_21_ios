# School 21 для iPhone

Неофициальный клиент платформы [platform.21-school.ru](https://platform.21-school.ru/) для iPhone и iPad.

> Приложение не связано со Школой 21 официально: показывает сайт платформы и данные её API, только читая их.
> Логин и пароль (если включить автовход) хранятся в Keychain iPhone и отправляются только на `auth.21-school.ru`.

## Экосистема School 21

| Устройство | Репозиторий | Скачать |
|---|---|---|
| Android | [school_21_mobile](https://github.com/Dlzxn/school_21_mobile) | [последний релиз](https://github.com/Dlzxn/school_21_mobile/releases/latest) |
| Windows · macOS · Linux | [school_21_desktop](https://github.com/Dlzxn/school_21_desktop) | [последний релиз](https://github.com/Dlzxn/school_21_desktop/releases/latest) |
| iPhone | [school_21_ios](https://github.com/Dlzxn/school_21_ios) | [последний релиз](https://github.com/Dlzxn/school_21_ios/releases/latest) |

🌐 Все версии и инструкции по установке на одной странице — **[sc21-apps.github.io](https://sc21-apps.github.io)**

## Возможности

- **Платформа на весь экран** — тёмная тема в цвет сайта, свайп «назад», pull-to-refresh, экран «Нет подключения».
- **Автовход** — платформа завершает сессию пару раз в день; приложение само вводит логин и пароль.
- **Закладки и стартовая страница** — «⋯» → «Закрепить эту страницу»; смахните закладку влево → ⌂, и приложение будет открываться сразу на ней.
- **Где сидит пир** — кластер, ряд и место по логину, уровень, коины, PRP/CRP, коалиция, логтайм.
- **Виджеты** на экран «Домой» (маленький и средний) и на экран блокировки.
- **Уведомления**: напоминания за 15 минут о событиях и проверках, на которые вы записаны (приходят вовремя),
  «колокольчик» платформы и новые события кампуса (iOS проверяет их в фоне сама, обычно раз в несколько часов).

## Установка без App Store (бесплатно)

Приложения нет в App Store — ставится через [AltStore](https://altstore.io) или [SideStore](https://sidestore.io)
с вашим обычным Apple ID.

1. Установите **AltServer** на компьютер (Windows или Mac) и через него — **AltStore** на iPhone
   ([инструкция](https://faq.altstore.io/)). На iPhone включите «Режим разработчика»: Настройки → Конфиденциальность и безопасность.
2. Скачайте `School21.ipa` из [последнего релиза](https://github.com/Dlzxn/school_21_ios/releases/latest) на iPhone.
3. AltStore → «My Apps» → «+» → выберите `School21.ipa`.

Ограничения бесплатного Apple ID (правила Apple):
- приложение нужно **переподписывать раз в 7 дней** — AltStore делает это сам, если iPhone и компьютер с AltServer
  бывают в одной Wi-Fi сети (или нажмите «Refresh All» в AltStore);
- не больше 3 таких приложений одновременно.

## Нашли баг?

Создайте [issue](https://github.com/Dlzxn/school_21_ios/issues): что делали, что ожидали, что получилось,
модель iPhone и версия iOS, скриншот. В приложении: «⋯» → «Настройки» → «Сообщить об ошибке».

Автор: [Dlzxn](https://github.com/Dlzxn) · School 21: combinef

## Разработка

Проект описан в `project.yml` ([XcodeGen](https://github.com/yonaskolb/XcodeGen)); `.xcodeproj` не хранится в git.

```bash
brew install xcodegen
xcodegen generate
open School21.xcodeproj
```

Без Mac: GitHub Actions (`.github/workflows/build.yml`) собирает неподписанный `School21.ipa` на каждый push
в `main` (артефакт сборки) и черновик релиза на тег `vX.Y.Z`.

```
School21/
├── App/        — точка входа, главный экран, конфиг
├── Web/        — WKWebView: навигация, ссылки, прогресс
├── Auth/       — Keychain, автовход, локальные уведомления
├── API/        — токены Keycloak, Open API, внутренний GraphQL (только чтение), проверка обновлений
├── Features/   — меню «⋯», закладки, «Где сидит пир», настройки
└── Sync/       — синхронизация, напоминания, фоновое обновление
Widget/         — виджеты WidgetKit
Shared/         — общие для приложения и виджета данные (App Group) и палитра
```
