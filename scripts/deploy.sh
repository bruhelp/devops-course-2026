#!/usr/bin/env bash
# Доставка статического ресурса на devops-vm
# Использование: scripts/deploy.sh [--dry-run]
set -euo pipefail

REMOTE="devops"                     # псевдоним из ~/.ssh/config
REMOTE_DIR="/var/www/devops-site"
SITE_URL="https://devops.local"
CA_CERT="${HOME}/devops.crt"
REPO_ROOT="$(git rev-parse --show-toplevel)"
LOCAL_DIR="${REPO_ROOT}/site/"

DRY_RUN=false
RSYNC_DRY=""

# 1. Разбор аргумента --dry-run
if [[ "${1:-}" == "--dry-run" ]]; then
    DRY_RUN=true
    RSYNC_DRY="--dry-run"
elif [[ -n "${1:-}" ]]; then
    echo "Ошибка: неизвестный аргумент '$1'" >&2
    exit 1
fi

# 2. Проверки по требованиям 4 и 5
# Требование 5: Проверка на незафиксированные изменения (включая индекс)
if [[ -n $(git status --porcelain) ]]; then
    echo "Ошибка: в репозитории есть незафиксированные изменения." >&2
    exit 16
fi

# Требование 4: Проверка существования файла site/index.html
if [[ ! -f "${LOCAL_DIR}/index.html" ]]; then
    echo "Ошибка: файл ${LOCAL_DIR}/index.html отсутствует." >&2
    exit 15
fi

# 8 & 9. Настройка rsync для работы через единое SSH-соединение без запроса пароля
RSYNC_RSH="ssh -o BatchMode=yes -o ConnectTimeout=5"

# 3. Синхронизация каталога с точным соответствием (--delete) и сохранением прав
# Права на сервере настраиваются по модели подраздела 2.4 (рекурсивно владелец www-data/деплой)
rsync -avz --delete ${RSYNC_DRY} -e "${RSYNC_RSH}" "${LOCAL_DIR}" "${REMOTE}:${REMOTE_DIR}"

# 4. При --dry-run — завершение с кодом 0 без проверки доступности
if [[ "${DRY_RUN}" == "true" ]]; then
    exit 0
fi

# 5. Проверка доступности ${SITE_URL} с использованием сертификата (требование 6)
# Используем curl -f для возврата ошибки при HTTP >= 400
if ! curl -s -f --cacert "${CA_CERT}" "${SITE_URL}" > /dev/null; then
    echo "Ошибка: ресурс ${SITE_URL} недоступен или проверка сертификата не прошла." >&2
    exit 17
fi

# 7. Успешное завершение — код 0 с выводом короткого хеша текущего коммита
git rev-parse --short HEAD