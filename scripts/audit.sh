#!/usr/bin/env bash
set -uo pipefail
PASS=0; FAIL=0

check() {
local desc="$1" expected="$2" actual="$3"
if [[ "$actual" == "$expected" ]]; then
echo "  [OK]   $desc"
((PASS++))
else
echo "  [FAIL] $desc (ожидалось: '$expected', получено: '$actual')"
((FAIL++))
fi
}

echo "Аудит конфигурации: $(hostname -f), $(date '+%Y-%m-%d %H:%M')"

echo "[1] Служба SSH"
check "Вход от имени root запрещён"        "no"  "$(sudo sshd -T | awk '/^permitrootlogin/{print $2}')"
check "Парольная аутентификация отключена" "no"  "$(sudo sshd -T | awk '/^passwordauthentication/{print $2}')"
# TODO 1: проверьте, что значение параметра port отлично от 22
check "Порт SSH отличен от 22 (текущий: 2222)" "2222" "$(sudo sshd -T | awk '/^port/{print $2}')"
# TODO 2: проверьте, что значение параметра maxauthtries равно 3
check "Максимальное число попыток входа (MaxAuthTries)" "3" "$(sudo sshd -T | awk '/^maxauthtries/{print $2}')"

echo "[2] Межсетевой экран"
check "Межсетевой экран активен" "active" "$(sudo ufw status | awk '/^Status:/{print $2}')"
# TODO 3: проверьте, что политика по умолчанию для входящего трафика равна deny
#         источник данных: sudo ufw status verbose | grep Default
check "Политика входящего трафика по умолчанию — deny" "deny" "$(sudo ufw status verbose | grep 'Default:' | awk '{print $2}' | tr -d '(incoming),')"

echo "[3] Учётные записи"
awk -F: '$3>=1000 && $3<65534 {printf "    %s (uid=%s)\n",$1,$3}' /etc/passwd

echo "[4] Веб-сервер"
# а) Проверка, что служба nginx активна
check "Служба Nginx активна" "active" "$(systemctl is-active nginx)"
# б) Проверка синтаксической корректности конфигурации Nginx
check "Конфигурация Nginx корректна" "0" "$(sudo nginx -t &>/dev/null; echo $?)"
# в) Проверка, что сертификат истекает не ранее чем через 30 дней
check "Сертификат действителен более 30 дней" "0" "$(openssl x509 -checkend 2592000 -noout -in /etc/s>
# г) Проверка отсутствия файлов, доступных для записи всем
check "Отсутствуют файлы сайта с правами o+w" "" "$(find /var/www/devops-site -perm -o+w 2>/dev/null)"
# г) Проверка прав на приватный ключ (600)
check "Права на приватный ключ равны 600" "600" "$(sudo stat -c '%a' /etc/ssl/private/devops.key)"

echo "[5] Контейнеризация"
check "Служба Docker активна" "active" "$(systemctl is-active docker)"
check "Контейнер СУБД в статусе healthy" "healthy" "$(docker inspect -f '{{.State.Health.Status}}' app-db-1 2>/dev/null || echo 'stopped')"
check "Порт 5000 слушает только 127.0.0.1" "1" "$(ss -tln | grep -E ':5000\b' | grep -c '127.0.0.1')"
check "Порт 5432 закрыт снаружи (не слушает интерфейсы)" "0" "$(ss -tln | grep -E ':5432\b' | wc -l)"
check "Права на файл .env равны 600" "600" "$(stat -c '%a' ~/app/.env 2>/dev/null || echo 'missing')"

echo "Пройдено: $PASS, не пройдено: $FAIL"
[[ $FAIL -eq 0 ]] && exit 0 || exit 1