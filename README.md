# RemoteApp — Obsidian Portable на Windows Server 2016 (рабочая группа)

Готовый набор для публикации **Obsidian Portable 1.10.6** в виде **RemoteApp** через RDP на **Windows Server 2016** в **рабочей группе** (без домена Active Directory, без Connection Broker, без интернета).

---

## Что внутри

```
RemoteApp/
├── ObsidianPortable/               # Obsidian Portable (PortableApps.com, v1.10.6)
│   └── App/AppInfo/Launcher/
│       └── ObsidianPortable.ini    # SinglePortableAppInstance=false + --user-data-dir per session
├── Инструкция/
│   ├── Настройка_Windows_Server_2016.md   # Пошаговая инструкция (шаги 0–5)
│   └── Obsidian_RemoteApp_Workgroup.rdp   # Шаблон .rdp для клиентов
└── scripts/
    └── Patch-RdpPassword.ps1       # Вшивает зашифрованный пароль (DPAPI) в .rdp
```

---

## Быстрый старт

### 1. Подготовить сервер

Прочитайте **[`Инструкция/Настройка_Windows_Server_2016.md`](Инструкция/Настройка_Windows_Server_2016.md)** — там пошаговое руководство:

| Шаг | Что делается |
|-----|-------------|
| 0 | Первичная проверка: сеть, профиль, брандмауэр, `hosts` |
| 1 | Локальный пользователь RDS, политика паролей |
| 2 | Копирование `ObsidianPortable` на сервер, права NTFS |
| 3 | Установка роли Remote Desktop Session Host (+Licensing) |
| 4 | Правило брандмауэра для TCP 3389 |
| 5 | Политики GPO для RemoteApp, шаблон `.rdp`, лимиты сеансов |

### 2. Скачать Obsidian Portable

Бинарники не включены в репозиторий (слишком большой размер). Скачайте архив **ObsidianPortable** с [portableapps.com/apps/office/obsidian-portable](https://portableapps.com/apps/office/obsidian-portable) (версия **1.10.6**) и распакуйте в папку `ObsidianPortable/` так, чтобы путь к лаунчеру был:

```
ObsidianPortable/ObsidianPortable.exe
```

Затем скопируйте из репозитория файл `ObsidianPortable/App/AppInfo/Launcher/ObsidianPortable.ini` поверх стандартного — он уже содержит правки для RDS (`SinglePortableAppInstance=false`, `--user-data-dir` per session).

### 3. Скопировать файлы на сервер

Рекомендуемое расположение:

```
D:\RemoteApp\ObsidianPortable\
D:\RemoteApp\Инструкция\
```

Затем выдайте группе **Прошедшие проверку подлинности** право **Изменение** на всю папку `ObsidianPortable` (подробнее — шаг 2 инструкции):

```cmd
icacls "D:\RemoteApp\ObsidianPortable" /grant *S-1-5-11:(OI)(CI)M /T
```

### 3. Настроить политики GPO на сервере

```
gpedit.msc →
  Конфигурация компьютера →
    Административные шаблоны →
      Компоненты Windows →
        Службы удалённых рабочих столов →
          Узел сеансов удалённых рабочих столов →
            Подключения:
              «Разрешать удаленный запуск любых программ» = Включено
```

### 4. Подготовить файл `.rdp` для клиентов

**Вариант А — вручную:** откройте `Инструкция/Obsidian_RemoteApp_Workgroup.rdp`, замените `YOUR-SERVER-NAME` и `YOUR-USERNAME`.

**Вариант Б — скрипт** (вшивает пароль, чтобы не вводить его каждый раз):

```powershell
# Запускайте под той же учётной записью Windows, с которой открываете .rdp
# Откройте scripts\Patch-RdpPassword.ps1 и заполните раздел CONFIG:
#   $RdpPath     = '...\Obsidian_RemoteApp_Workgroup.rdp'
#   $RdpUsername = 'SERVER\obsidian'
#   $RdpPassword = 'yourpassword'

powershell -File .\scripts\Patch-RdpPassword.ps1
```

> **Важно:** зашифрованный пароль привязан к текущему профилю Windows на этом ПК (DPAPI).  
> Не коммитьте `.rdp`-файлы с паролем в git.

### 5. Открыть на клиенте Windows 7 / 10

Скопируйте готовый `.rdp` на клиент и дважды щёлкните. Obsidian откроется в плавающем окне RemoteApp.

---

## Несколько одновременных пользователей

`ObsidianPortable.ini` уже настроен на изолированные профили Electron для каждого сеанса:

```ini
SinglePortableAppInstance=false
CommandLineArguments=--user-data-dir="%PAL:DataDir%\ObsidianAppData-rds-%USERNAME%-%SESSIONNAME%"
```

При первом запуске нового профиля Obsidian попросит открыть vault — укажите  
`D:\RemoteApp\ObsidianPortable\Data\Obsidian Vault` (или ваше хранилище).

> Один vault, два активных сеанса одновременно — риск конфликтов данных.  
> Для параллельной работы используйте разные хранилища или разных пользователей.

---

## Завершение сеанса

В режиме чистого RemoteApp (плавающее окно без панели задач сервера) стандартные команды выхода (`Ctrl+Q`, `Alt+F4`, палитра) могут не работать — это ограничение Electron + PortableApps в RDP.  
**Решение:** закрыть окно кнопкой × клиента или разорвать сеанс. Если при следующем запуске PortableApps покажет диалог «не закрылся должным образом» — нажмите **OK**, затем снова откройте `.rdp`.

---

## Лицензирование

| Компонент | Лицензия |
|-----------|----------|
| Obsidian | [Obsidian Terms of Service](https://obsidian.md/terms) (бесплатно для личного использования) |
| PortableApps.com Launcher | [GPL](https://portableapps.com/about/open_source) |
| Windows Server 2016 RDS | Требуются **RDS CAL** (льготный период ~120 дней без CAL) |
| Этот репозиторий (скрипты, конфиги, инструкция) | [MIT](LICENSE) |

> Роли RDS требуют лицензий Microsoft RDS CAL для каждого пользователя/устройства.  
> Убедитесь, что ваш сценарий соответствует условиям лицензирования.

---

## Требования

- **Сервер:** Windows Server 2016 (протестировано), роль Remote Desktop Session Host
- **Клиент:** Windows 7 SP1+ или Windows 10/11, клиент mstsc
- **Сеть:** ЛВС без интернета, TCP 3389 открыт, статический IP или имя сервера в `hosts`

---

## Ссылки

- [Инструкция по настройке сервера](Инструкция/Настройка_Windows_Server_2016.md)
- [Microsoft: установка RDSH без Connection Broker](https://learn.microsoft.com/troubleshoot/windows-server/remote/install-rds-host-role-service-without-connection-broker)
- [Microsoft: RemoteApp sessions disconnected](https://learn.microsoft.com/en-us/troubleshoot/windows-server/remote/remoteapp-sessions-disconnected)
- [Microsoft: RDS Client Access Licensing](https://learn.microsoft.com/windows-server/remote/remote-desktop-services/rds-client-access-license)
- [Obsidian Portable на PortableApps.com](https://portableapps.com/apps/office/obsidian-portable)
