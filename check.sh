#!/bin/bash

# Validates the position of a Survey Point by comparing the coordinates of
# the element and the corresponding tags.
#
# For Latitude, the element retrieves the lat property, and the element should
# have a tag like:
# * lat
# * latitude
# For Longitude, the element retrieves the long property, and the element
# should have a tag like:
# * lon
# * longitude
#
# Both, latitude and longitude tags are rounded to 7 decimals. If it has less
# then it will return an precision error.
#
# To check the last execution, you can just run:
#   cd $(find /tmp/ -name "check_*" -type d -printf "%T@ %p\n" 2> /dev/null | sort -n | cut -d' ' -f 2- | tail -n 1) ; tail -f check.log ; cd -
#
# The following environment variables helps to configure the script:
# * CLEAN_FILES : Cleans all files at the end.
# * EMAILS : List of emails to send the report, separated by comma.
# * LOG_LEVEL : Log level in capitals.
#
# export EMAILS="angoca@yahoo.com" ; export LOG_LEVEL=WARN; cd ~/SurveyPoints-validator ; ./check.sh
#
# Author: Andres Gomez
# Version: 2023-09-29
declare -r VERSION="2023-09-29"

#set -xv
# Fails when a variable is not initialized.
set -u
# Fails with a non-zero return code.
set -e
# Fails if the commands of a pipe return non-zero.
set -o pipefail
# Fails if an internal function fails.
set -E

# Error codes.
# 1: Help message.
declare -r ERROR_HELP_MESSAGE=1
# 241: Library or utility missing.
declare -r ERROR_MISSING_LIBRARY=241
# 243: Logger utility is not available.
declare -r ERROR_LOGGER_UTILITY=242

# Logger levels: TRACE, DEBUG, INFO, WARN, ERROR, FATAL.
declare LOG_LEVEL="${LOG_LEVEL:-ERROR}"

# Clean files.
declare CLEAN_FILES="${CLEAN_FILES:-true}"

# Base directory, where the script resides.
# Taken from https://stackoverflow.com/questions/59895/how-can-i-get-the-source-directory-of-a-bash-script-from-within-the-script-itsel
# shellcheck disable=SC2155
declare -r SCRIPT_BASE_DIRECTORY="$(cd "$(dirname "${BASH_SOURCE[0]}")" \
  &> /dev/null && pwd)"

# Logger framework.
# Taken from https://github.com/DushyanthJyothi/bash-logger.
declare -r LOGGER_UTILITY="${SCRIPT_BASE_DIRECTORY}/bash_logger.sh"

# Mask for the files and directories.
umask 0000

# Name of this script.
declare BASENAME
BASENAME=$(basename -s .sh "${0}")
readonly BASENAME
# Temporal directory for all files.
declare TMP_DIR
TMP_DIR=$(mktemp -d "/tmp/${BASENAME}_XXXXXX")
readonly TMP_DIR
# Log file for output.
declare LOG_FILE
LOG_FILE="${TMP_DIR}/${BASENAME}.log"
readonly LOG_FILE

# Type of process to run in the script.
declare -r PROCESS_TYPE=${1:-}

# Query file.
declare -r QUERY_FILE=${TMP_DIR}/query.txt
# Downloaded survey points.
declare -r SURVEY_POINTS=${TMP_DIR}/survey_points.txt
# Report file.
declare -r REPORT=${TMP_DIR}/report.txt
# Report content.
declare -r REPORT_CONTENT=${TMP_DIR}/reportContent.txt
# Mails to send the report.
declare -r EMAILS="${EMAILS:-angoca@yahoo.com}"

###########
# FUNCTIONS

### Logger

# Loads the logger (log4j like) tool.
# It has the following functions.
# __log default.
# __logt for trace.
# __logd for debug.
# __logi for info.
# __logw for warn.
# __loge for error. Writes in standard error.
# __logf for fatal.
# Declare mock functions, in order to have them in case the logger utility
# cannot be found.
function __log() { :; }
function __logt() { :; }
function __logd() { :; }
function __logi() { :; }
function __logw() { :; }
function __loge() { :; }
function __logf() { :; }
function __log_start() { :; }
function __log_finish() { :; }

# Starts the logger utility.
function __startLogger() {
 if [[ -f "${LOGGER_UTILITY}" ]] ; then
  # Starts the logger mechanism.
  set +e
  # shellcheck source=./bash_logger.sh
  source "${LOGGER_UTILITY}"
  local -i RET=${?}
  set -e
  if [[ "${RET}" -ne 0 ]] ; then
   printf "\nERROR: El archivo de framework de logger es inválido.\n"
   exit "${ERROR_LOGGER_UTILITY}"
  fi
  # Logger levels: TRACE, DEBUG, INFO, WARN, ERROR.
  __bl_set_log_level "${LOG_LEVEL}"
  __logd "Logger adicionado."
 else
  printf "\nLogger no fue encontrado.\n"
 fi
}

# Function that activates the error trap.
function __trapOn() {
 __log_start
 trap '{ printf "%s ERROR: El script no terminó correctamente. Número de línea: %d.\n" "$(date +%Y%m%d_%H:%M:%S)" "${LINENO}"; exit ;}' \
   ERR
 trap '{ printf "%s WARN: El script fue terminado.\n" "$(date +%Y%m%d_%H:%M:%S)"; exit ;}' \
   SIGINT SIGTERM
 __log_finish
}

# Shows the help information.
function __showHelp {
 echo "${BASENAME} version ${VERSION}"
 echo "Este script verifica las coordenadas del elemento y se las etiquetas"
 echo "para corroborar que está bien ubicado."
 echo "Busca todos los elementos man_made=survey_point de Colombia."
 echo
 echo "Para cambiar los destinatarios del reporte enviado por correo"
 echo "electrónico, se modifica la variable de entorno EMAILS:"
 echo "  export EMAILS=\"maptime.bogota@gmail.com,contact@osm.org\""
 echo
 echo "Escrito por: Andres Gomez (AngocA)"
 echo "MaptimeBogota."
 exit "${ERROR_HELP_MESSAGE}"
}

# Checks prerequisites to run the script.
function __checkPrereqs {
 __log_start
 set +e
 # Checks prereqs.
 ## Wget.
 if ! wget --version > /dev/null 2>&1 ; then
  __loge "Falta instalar wget."
  exit "${ERROR_MISSING_LIBRARY}"
 fi
 ## Mutt.
 if ! mutt -v > /dev/null 2>&1 ; then
  __loge "Falta instalar mutt."
  exit "${ERROR_MISSING_LIBRARY}"
 fi
 ## flock.
 if ! flock --version > /dev/null 2>&1 ; then
  __loge "Falta instalar flock."
  exit "${ERROR_MISSING_LIBRARY}"
 fi
 ## Bash 4 or greater.
 if [[ "${BASH_VERSINFO[0]}" -lt 4 ]] ; then
  __loge "Requiere Bash 4+."
  exit "${ERROR_MISSING_LIBRARY}"
 fi
 __log_finish
 set -e
}

# Prepares and checks the environment to keep the history of the elements.
function __prepareEnv {
 __log_start
 cat << EOF > "${REPORT}"
Validación de ubicación de puntos geodésicos (survey point) en Colombia
sobre OpenStreetMap.

Hora de inicio: $(date || true).

EOF
 __log_finish
}

# Generates the query file.
function __generateQuery {
 __log_start
 cat << EOF > "${QUERY_FILE}"
[out:csv(::id,::lat,"latitude",::lon,"longitude"; false; ",")][timeout:25];
area[name="Colombia"][admin_level=2]->.searchArea;
(
  node["man_made"="survey_point"]["latitude"]["longitude"](area.searchArea);
);
out body;
>;
out skel qt;
EOF
 __log_finish
}

# Retrieves all nodes for survey_points.
function __getSurveyPoints {
 __log_start
 __logi "Obtiene los puntos geodésicos."

 wget -O "${SURVEY_POINTS}" --post-file="${QUERY_FILE}" "https://overpass-api.de/api/interpreter" >> "${LOG_FILE}" 2>&1
 RET=${?}
 if [[ "${RET}" -ne 0 ]] ; then
  __loge "Falló la descarga de los ids."
  exit "${ERROR_DOWNLOADING_IDS}"
 fi
 __log_finish
}

# For every single survey point, it checks the coordinates.
function __checkLongitudeLatitude {
 __log_start
 __logi "Valida la ubicación de cada uno de los puntos geodésicos."
 # Iterates over each survey point.
 while read -r LINE ; do
  ID=$(echo "${LINE}" | cut -d, -f1)
  LAT_ELE=$(echo "${LINE}" | cut -d, -f2)
  LAT_TAG=$(echo "${LINE}" | cut -d, -f3)
  LON_ELE=$(echo "${LINE}" | cut -d, -f4)
  LON_TAG=$(echo "${LINE}" | cut -d, -f5)
  __logi "Procesando punto geodésico id ${ID}."
  LAT_TAG_7=$(printf "%.7f" "${LAT_TAG}")
  LON_TAG_7=$(printf "%.7f" "${LON_TAG}")

  if (( $(echo "${LAT_ELE} > ${LAT_TAG_7}" | bc -l) )) ; then
   printf "Error precisión latitud:  <pre>Ele %12.7f, Tag %12.7f</pre> - https://www.openstreetmap.org/node/%d.\n" "${LAT_ELE}" "${LAT_TAG_7}" "${ID}" >> ${REPORT_CONTENT}
  fi
  if (( $(echo "${LON_ELE} > ${LON_TAG_7}" | bc -l) )) ; then
   printf "Error precisión longitud: <pre>Ele %12.7f, Tag %12.7f</pre> - https://www.openstreetmap.org/node/%d.\n" "${LON_ELE}" "${LON_TAG_7}" "${ID}" >> ${REPORT_CONTENT}
  fi
 done < "${SURVEY_POINTS}"
 __log_finish
}

# Sends the report of the modified elements.
function __sendMail {
 __log_start
 if [[ -f "${REPORT_CONTENT}" ]] ; then
  __logi "Enviando mensaje por correo electrónico."
  {
   cat "${REPORT_CONTENT}"
   echo
   echo "Hora de fin: $(date || true)"
   echo
   echo "Este reporte fue creado por medio del script de chequeo:"
   echo "https://github.com/MaptimeBogota/SurveyPoints-validator"
  } >> "${REPORT}"
  echo "" | mutt -s "Revisión de ubicación de puntos geodésicos" -i "${REPORT}" -- "${EMAILS}" >> "${LOG_FILE}"
  __logi "Mensaje enviado."
 fi
 __log_finish
}

# Clean unnecessary files.
function __cleanFiles {
 __log_start
 if [ "${CLEAN_FILES}" = "true" ] ; then
  __logi "Limpiando archivos innecesarios."
  rm -f "${QUERY_FILE}" "${SURVEY_POINTS}" "${REPORT}"
 fi
 __log_finish
}

######
# MAIN

# Allows to other user read the directory.
chmod go+x "${TMP_DIR}"

{
 __startLogger
 __logi "Preparando el ambiente."
 __logd "Salida guardada en: ${TMP_DIR}."
 __logi "Procesando tipo de elemento: ${PROCESS_TYPE}."
} >> "${LOG_FILE}" 2>&1

if [[ "${PROCESS_TYPE}" == "-h" ]] || [[ "${PROCESS_TYPE}" == "--help" ]]; then
 __showHelp
fi
__checkPrereqs
{
 __logw "Comenzando el proceso."
} >> "${LOG_FILE}" 2>&1

# Sets the trap in case of any signal.
__trapOn

{
 __prepareEnv
 __generateQuery
 __getSurveyPoints
 __checkLongitudeLatitude
 __sendMail
 __cleanFiles
 __logw "Proceso terminado."
} >> "${LOG_FILE}" 2>&1

