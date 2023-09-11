#!/bin/bash

CERT_FILES=(
  'cert.pem'
  'privkey.pem'
  'fullchain.pem'
)

# path of this script
BASE_ROOT=$(
  cd "$(dirname "$0")"
  pwd
)
# date time
DATE_TIME=$(date +%Y%m%d%H%M%S)
# base crt path
CRT_BASE_PATH=/usr/syno/etc/certificate
PKG_CRT_BASE_PATH=/usr/local/etc/certificate
ACME_BIN_PATH=~/.acme.sh
ACME_CRT_PATH=~/certificates
TEMP_PATH=~/temp
ARCHIEV_PATH="${CRT_BASE_PATH}/_archive"
INFO_FILE_PATH="${ARCHIEV_PATH}/INFO"

# 定义代理服务器地址和端口
PROXY_SERVER=http://10.10.10.200:1087

# 定义日志文件
LOG_FILE="$(dirname "$0")/cert-up.log"

# 清空日志文件
: > "$LOG_FILE"

if [ ! -d ${ACME_BIN_PATH} ]; then
  mkdir ${ACME_BIN_PATH}
fi
if [ ! -d ${ACME_CRT_PATH} ]; then
  mkdir ${ACME_CRT_PATH}
fi
has_config=false
if [ -f ${ACME_BIN_PATH}/config ]; then
  has_config=true
  source ${ACME_BIN_PATH}/config
else
  has_config=false
fi
do_register=false
if [ "$has_config" = true ] && [ ! -f ${ACME_BIN_PATH}/registed ]; then
  do_register=true
fi

backup_cert() {
  echo "$(date '+%Y-%m-%d %H:%M:%S') - begin backup_cert" | tee -a "$LOG_FILE"
  BACKUP_PATH=~/cert_backup/${DATE_TIME}
  mkdir -p ${BACKUP_PATH}
  cp -r ${CRT_BASE_PATH} ${BACKUP_PATH}
  cp -r ${PKG_CRT_BASE_PATH} ${BACKUP_PATH}/package_cert
  echo ${BACKUP_PATH} >~/cert_backup/latest
  echo "$(date '+%Y-%m-%d %H:%M:%S') - done backup_cert" | tee -a "$LOG_FILE"
  return 0
}

install_acme() {
  echo "$(date '+%Y-%m-%d %H:%M:%S') - begin install_acme" | tee -a "$LOG_FILE"
  mkdir -p ${TEMP_PATH}
  rm -rf ${TEMP_PATH}/acme.sh
  cd ${TEMP_PATH}
  echo "$(date '+%Y-%m-%d %H:%M:%S') - begin downloading acme.sh tool..." | tee -a "$LOG_FILE"
  LATEST_URL=$(curl -x $PROXY_SERVER -Ls -o /dev/null -w %{url_effective} https://github.com/acmesh-official/acme.sh/releases/latest 2>&1)
  ACME_SH_ADDRESS=${LATEST_URL//releases\/tag\//archive\/}.tar.gz
  SRC_TAR_NAME=acme.sh.tar.gz
  curl -x $PROXY_SERVER -L -o ${SRC_TAR_NAME} ${ACME_SH_ADDRESS}
  if [ ! -f ${TEMP_PATH}/${SRC_TAR_NAME} ]; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') - download acme.sh failed"  | tee -a "$LOG_FILE"
    exit 1
  fi
  SRC_NAME=$(tar -tzf ${SRC_TAR_NAME} | head -1 | cut -f1 -d"/")
  tar zxvf ${SRC_TAR_NAME}
  if [ ! -d ${TEMP_PATH}/${SRC_NAME} ]; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') - the file downloaded incorrectly" | tee -a "$LOG_FILE"
    exit 1
  fi
  echo "$(date '+%Y-%m-%d %H:%M:%S') - begin installing acme.sh tool..." | tee -a "$LOG_FILE"
  if [ "$has_config" = true ]; then
    emailpara="--accountemail \"${EMAIL}\""
  else
    cp ${BASE_ROOT}/config ${ACME_BIN_PATH}
    emailpara=''
    echo !! please fill out the ${BASE_ROOT}/config and then run \"$0 update\"
  fi
  cd ${SRC_NAME}
  ./acme.sh --install --nocron --home ${ACME_BIN_PATH} --cert-home ${ACME_CRT_PATH} ${emailpara}
  echo "$(date '+%Y-%m-%d %H:%M:%S') - done install_acme"  | tee -a "$LOG_FILE"
  rm -rf ${TEMP_PATH}/{${SRC_NAME},${SRC_TAR_NAME}}
  return 0
}

register_account() {
  cd ${ACME_BIN_PATH}
  ${ACME_BIN_PATH}/acme.sh --register-account -m "${EMAIL}"
  if [ $? -ne 0 ]; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') - register_account failed!!" | tee -a "$LOG_FILE"
    return 1
  fi
  touch ${ACME_BIN_PATH}/registed
  echo "$(date '+%Y-%m-%d %H:%M:%S') - done register_account" | tee -a "$LOG_FILE"
  return 0
}

generate_cert() {
  if [ "$do_register" = true ]; then
    # first register account
    register_account
    if [ $? -ne 0 ]; then
      exit 1
    fi
  fi
  echo "$(date '+%Y-%m-%d %H:%M:%S') - begin generate_cert" | tee -a "$LOG_FILE"
  cd ${ACME_BIN_PATH}
  source "${ACME_BIN_PATH}/acme.sh.env"
  echo "$(date '+%Y-%m-%d %H:%M:%S') - begin updating default cert by acme.sh tool" | tee -a "$LOG_FILE"
  ${ACME_BIN_PATH}/acme.sh --force --log --issue --dns ${DNS} --dnssleep ${DNS_SLEEP} -d "${DOMAIN}" -d "*.${DOMAIN}" -k 4096 --force >> "$LOG_FILE" 2>&1
  if [ $? -eq 0 ] && [ -s ${ACME_CRT_PATH}/${DOMAIN}/ca.cer ]; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') - done generate_cert" | tee -a "$LOG_FILE"
    return 0
  else
    echo "$(date '+%Y-%m-%d %H:%M:%S') - [ERROR] fail to generate_cert" | tee -a "$LOG_FILE"
    exit 1
  fi
}

update_service() {
  echo "$(date '+%Y-%m-%d %H:%M:%S') - begin update_service" | tee -a "$LOG_FILE"

  CRT_PATH_NAME=$(cat ${ARCHIEV_PATH}/DEFAULT)
  CRT_PATH=${ARCHIEV_PATH}/${CRT_PATH_NAME}
  services=()
  info=$(cat "$INFO_FILE_PATH")
  if [ -z "$info" ]; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Failed to read file: $INFO_FILE_PATH" | tee -a "$LOG_FILE"
    exit 1
  else
	services=($(echo "$info" | jq -r ".\"$CRT_PATH_NAME\".services[] | @base64"))
  fi
  if [[ ${#services[@]} -eq 0 ]]; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') - [ERROR] load INFO file - $INFO_FILE_PATH fail"  | tee -a "$LOG_FILE"
    exit 1
  fi

  if [ -e ${ACME_CRT_PATH}/${DOMAIN}/ca.cer ] && [ -s ${ACME_CRT_PATH}/${DOMAIN}/ca.cer ]; then
    cp -v ${ACME_CRT_PATH}/${DOMAIN}/ca.cer ${CRT_PATH}/chain.pem
    cp -v ${ACME_CRT_PATH}/${DOMAIN}/fullchain.cer ${CRT_PATH}/fullchain.pem
    cp -v ${ACME_CRT_PATH}/${DOMAIN}/${DOMAIN}.cer ${CRT_PATH}/cert.pem
    cp -v ${ACME_CRT_PATH}/${DOMAIN}/${DOMAIN}.key ${CRT_PATH}/privkey.pem
    for service in "${services[@]}"; do
      display_name=$(echo "$service" | base64 --decode | jq -r '.display_name')
      isPkg=$(echo "$service" | base64 --decode | jq -r '.isPkg')
      subscriber=$(echo "$service" | base64 --decode | jq -r '.subscriber')
      service_name=$(echo "$service" | base64 --decode | jq -r '.service')

      echo "Copy cert for $display_name"
      if [[ $isPkg == true ]]; then
        CP_TO_DIR="${PKG_CRT_BASE_PATH}/${subscriber}/${service_name}"
      else
        CP_TO_DIR="${CRT_BASE_PATH}/${subscriber}/${service_name}"
      fi
      for f in "${CERT_FILES[@]}"; do
        src="$CRT_PATH/$f"
        des="$CP_TO_DIR/$f"
        if [[ -e "$des" ]]; then
          rm -fr "$des"
        fi
        cp -v "$src" "$des" || echo "[WRN] copy from $src to $des fail"
      done
    done
    echo "$(date '+%Y-%m-%d %H:%M:%S') - done update_service"  | tee -a "$LOG_FILE"
  else
    echo "$(date '+%Y-%m-%d %H:%M:%S') - no cert files, pls run: $0 generate_cert" | tee -a "$LOG_FILE"
  fi
}

reload_webservice() {
  echo "$(date '+%Y-%m-%d %H:%M:%S') - begin reload_webservice" | tee -a "$LOG_FILE"
}

revert_cert() {
  echo "$(date '+%Y-%m-%d %H:%M:%S') - begin revert_cert" | tee -a "$LOG_FILE"
  BACKUP_PATH=~/cert_backup/$1
  if [ -z "$1" ]; then
    if [ ! -f ~/cert_backup/latest ]; then
      echo "$(date '+%Y-%m-%d %H:%M:%S') - [ERROR] backup file: ~/cert_backup/latest not found." | tee -a "$LOG_FILE"
      return 1
    fi
    BACKUP_PATH=$(cat ~/cert_backup/latest)
  fi
  if [ ! -d "${BACKUP_PATH}" ]; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') - [ERROR] backup path: ${BACKUP_PATH} not found."  | tee -a "$LOG_FILE"
    return 1
  fi
  echo "${BACKUP_PATH}/certificate ${CRT_BASE_PATH}"
  cp -rf ${BACKUP_PATH}/certificate/* ${CRT_BASE_PATH}
  echo "${BACKUP_PATH}/package_cert ${PKG_CRT_BASE_PATH}"
  cp -rf ${BACKUP_PATH}/package_cert/* ${PKG_CRT_BASE_PATH}
  reload_webservice
  echo "$(date '+%Y-%m-%d %H:%M:%S') - done revert_cert"  | tee -a "$LOG_FILE"
}

case "$1" in
install)
  echo "------ install script ------"
  install_acme
  ;;

backup_cert)
  echo "------ backup_cert ------"
  backup_cert
  ;;

generate_cert)
  echo "------ generate_cert ------"
  generate_cert
  ;;

update_service)
  echo "------ update_service ------"
  update_service
  ;;

reload_webservice)
  echo "------ reload_webservice ------"
  reload_webservice
  ;;

update)
  echo '------ update_cert ------'
  backup_cert
  generate_cert
  update_service
  reload_webservice
  ;;

register)
  echo "------ register_account ------"
  register_account
  ;;

revert)
  echo "------ revert ------"
  revert_cert $2
  ;;

*)
  echo "Usage: $0 {install|update|register|revert}"
  echo or
  echo "Usage: $0 {install|backup_cert|generate_cert|update_service|reload_webservice|register|revert}"
  exit 1
  ;;
esac
