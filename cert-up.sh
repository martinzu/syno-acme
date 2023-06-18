#!/bin/bash

# path of this script
BASE_ROOT=$(cd "$(dirname "$0")";pwd)
# date time
DATE_TIME=`date +%Y%m%d%H%M%S`
# base crt path
CRT_BASE_PATH=/usr/syno/etc/certificate
PKG_CRT_BASE_PATH=/usr/local/etc/certificate
ACME_BIN_PATH=~/.acme.sh
ACME_CRT_PATH=~/certificates
TEMP_PATH=~/temp
CRT_PATH_NAME=`sudo cat ${CRT_BASE_PATH}/_archive/DEFAULT`
CRT_PATH=${CRT_BASE_PATH}/_archive/${CRT_PATH_NAME}

SYNCTHING_PATH=/volume1/@appdata/syncthing
# Before DSM 7.0, use the following instead:
#SYNCTHING_PATH=/var/packages/syncthing/target/var
SYNCTHING_USER=sc-syncthing
SYNCTHING_GROUP=synocommunity

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
  SYNCTHING=false
fi
do_register=false
if [ "$has_config" = true ] && [ ! -f ${ACME_BIN_PATH}/registed ]; then
  do_register=true
fi

backup_cert () {
  echo 'begin backup_cert'
  BACKUP_PATH=~/cert_backup/${DATE_TIME}
  mkdir -p ${BACKUP_PATH}
  sudo cp -r ${CRT_BASE_PATH} ${BACKUP_PATH}
  sudo cp -r ${PKG_CRT_BASE_PATH} ${BACKUP_PATH}/package_cert
  echo ${BACKUP_PATH} > ~/cert_backup/latest
  echo 'done backup_cert'
  return 0
}

install_acme () {
  echo 'begin install_acme'
  mkdir -p ${TEMP_PATH}
  rm -rf ${TEMP_PATH}/acme.sh
  cd ${TEMP_PATH}
  echo 'begin downloading acme.sh tool...'
  LATEST_URL=$(curl -Ls -o /dev/null -w %{url_effective} https://github.com/acmesh-official/acme.sh/releases/latest 2>&1)
  ACME_SH_ADDRESS=${LATEST_URL//releases\/tag\//archive\/}.tar.gz
  SRC_TAR_NAME=acme.sh.tar.gz
  curl -L -o ${SRC_TAR_NAME} ${ACME_SH_ADDRESS}
  if [ ! -f ${TEMP_PATH}/${SRC_TAR_NAME} ]; then
    echo 'download failed'
    exit 1;
  fi
  SRC_NAME=`tar -tzf ${SRC_TAR_NAME} | head -1 | cut -f1 -d"/"`
  tar zxvf ${SRC_TAR_NAME}
  if [ ! -d ${TEMP_PATH}/${SRC_NAME} ]; then
    echo 'the file downloaded incorrectly'
    exit 1;
  fi
  # OR git master
  #git clone https://github.com/acmesh-official/acme.sh.git
  #if [ $? -ne 0 ]; then
  #  echo "download failed"
  #  exit 1;
  #fi
  #SRC_NAME=acme.sh
  echo 'begin installing acme.sh tool...'
  if [ "$has_config" = true ]; then
    emailpara="--accountemail \"${EMAIL}\""
  else
    cp ${BASE_ROOT}/config ${ACME_BIN_PATH}
    emailpara=''
    echo !! please fill out the ${BASE_ROOT}/config and then run \"$0 update\"
  fi
  cd ${SRC_NAME}
  ./acme.sh --install --nocron --home ${ACME_BIN_PATH} --cert-home ${ACME_CRT_PATH} ${emailpara}
  echo 'done install_acme'
  rm -rf ${TEMP_PATH}/{${SRC_NAME},${SRC_TAR_NAME}}
  return 0
}

register_account () {
  cd ${ACME_BIN_PATH}
  ${ACME_BIN_PATH}/acme.sh --register-account -m "${EMAIL}"
  if [ $? -ne 0 ]; then
    echo 'register_account failed!!'
    return 1;
  fi
  touch ${ACME_BIN_PATH}/registed
  echo 'done register_account'
  return 0
}

generate_cert () {
  if [ "$do_register" = true ]; then
    # first register account
    register_account
    if [ $? -ne 0 ]; then
      exit 1
    fi
  fi
  echo 'begin generate_cert'
  cd ${ACME_BIN_PATH}
  echo 'begin updating default cert by acme.sh tool'
  source "${ACME_BIN_PATH}/acme.sh.env"
  ${ACME_BIN_PATH}/acme.sh --force --log --issue --dns ${DNS} --dnssleep ${DNS_SLEEP} -d \"${DOMAIN}\" -d \"*.${DOMAIN}\"
  #   --cert-file ${ACME_CRT_PATH}/cert.pem \
  #   --key-file ${ACME_CRT_PATH}/privkey.pem \
  #   --ca-file ${ACME_CRT_PATH}/chain.pem \
  #   --fullchain-file ${ACME_CRT_PATH}/fullchain.pem
  if [ $? -eq 0 ] && [ -s ${ACME_CRT_PATH}/${DOMAIN}/ca.cer ]; then
    sudo cp ${ACME_CRT_PATH}/${DOMAIN}/ca.cer ${CRT_PATH}/chain.pem
    sudo cp ${ACME_CRT_PATH}/${DOMAIN}/fullchain.cer ${CRT_PATH}/fullchain.pem
    sudo cp ${ACME_CRT_PATH}/${DOMAIN}/${DOMAIN}.cer ${CRT_PATH}/cert.pem
    sudo cp ${ACME_CRT_PATH}/${DOMAIN}/${DOMAIN}.key ${CRT_PATH}/privkey.pem
    echo 'done generate_cert'
    return 0
  else
    echo '[ERR] fail to generate_cert'
    echo "begin revert"
    revert_cert
    exit 1;
  fi
}

update_service () {
  echo 'begin update_service'
  sudo /bin/python ${BASE_ROOT}/cert_cp.py ${CRT_PATH_NAME}
  if [ "$SYNCTHING" = true ]; then
    echo 'Copy cert for Syncthing'
    sudo cp -v --preserve=timestamps ${CRT_PATH}/cert.pem ${SYNCTHING_PATH}/https-cert.pem
    sudo cp -v --preserve=timestamps ${CRT_PATH}/privkey.pem ${SYNCTHING_PATH}/https-key.pem
    sudo chmod 664 ${SYNCTHING_PATH}/https-cert.pem
    sudo chmod 600 ${SYNCTHING_PATH}/https-key.pem
    sudo chown ${SYNCTHING_USER}:${SYNCTHING_GROUP} ${SYNCTHING_PATH}/https-cert.pem
    sudo chown ${SYNCTHING_USER}:${SYNCTHING_GROUP} ${SYNCTHING_PATH}/https-key.pem
  fi
  echo 'done update_service'
}

reload_webservice () {
  echo 'begin reload_webservice'

  # Not all Synology NAS webservice are the same.
  # Write code according to your configuration.
  #echo 'reloading new cert...'
  #/usr/syno/etc/rc.sysv/nginx.sh reload
  #echo 'relading Apache 2.2'
  #stop pkg-apache22
  #start pkg-apache22
  #reload pkg-apache22
  #echo 'done reload_webservice'

  if [ "$SYNCTHING" = true ]; then
    curl -k -X POST -H "X-API-Key: ${SYNCTHING_API_KEY}" https://localhost:8384/rest/system/restart
  fi
}

revert_cert () {
  echo 'begin revert_cert'
  BACKUP_PATH=${BASE_ROOT}/backup/$1
  if [ -z "$1" ]; then
    BACKUP_PATH=`cat ${BASE_ROOT}/backup/latest`
  fi
  if [ ! -d "${BACKUP_PATH}" ]; then
    echo "[ERR] backup path: ${BACKUP_PATH} not found."
    return 1
  fi
  echo "${BACKUP_PATH}/certificate ${CRT_BASE_PATH}"
  sudo cp -rf ${BACKUP_PATH}/certificate/* ${CRT_BASE_PATH}
  echo "${BACKUP_PATH}/package_cert ${PKG_CRT_BASE_PATH}"
  sudo cp -rf ${BACKUP_PATH}/package_cert/* ${PKG_CRT_BASE_PATH}
  reload_webservice
  echo 'done revert_cert'
}

update_cert () {
  echo '------ begin update_cert ------'
  backup_cert
  generate_cert
  update_service
  reload_webservice
  echo '------ end update_cert ------'
}

case "$1" in
install)
  echo "begin install script"
  install_acme
  ;;

update)
  echo "begin update cert"
  update_cert
  ;;

register)
  echo "begin register_account"
  register_account
  ;;

revert)
  echo "begin revert"
  revert_cert $2
  ;;

*)
  echo "Usage: $0 {install|update|register|revert}"
  exit 1
esac
