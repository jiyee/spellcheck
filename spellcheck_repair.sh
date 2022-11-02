#!/bin/bash

# set -euo pipefail
# IFS=
# set -vx

RES='\033[0m'
RED_COLOR='\033[0;31m'
GREEN_COLOR='\033[0;32m'

echo_success() {
  echo -e "${GREEN_COLOR}$1${RES}" 
}

echo_error() {
  echo -e "${RED_COLOR}$1${RES}" 
}

$(which q > /dev/null) || {
  brew install q
}

$(which fd > /dev/null) || {
  brew install fd
}

version() { echo "$@" | awk -F. '{ printf("%d%03d%03d%03d\n", $1, $2, $3, $4); }'; }
if [[ $(version "$(fd --version | cut -d' ' -f2)") -lt $(version "8.4.0") ]]; then
  echo_error "'fd' version should be 8.4.0 or higher"
  exit 1
fi

$(which rg > /dev/null) || {
  brew install ripgrep
}

help() {
  echo ""
  echo "Usage: $0 -d <scan_dir> -e <exclude_dir> -c <command>"
  echo -e "\t-d <scan_dir>    spellcheck_repair target directory, like ./Module"
  echo -e "\t-e <exclude_dir> spellcheck_repair exclude directory, like ./Pods"
  echo -e "\t-c <command>     spellcheck_repair command, list below:"
  echo -e "\t   scan          scan misspelling in file path and source code"
  echo -e "\t   repair_path   repair misspelling in file path"
  echo -e "\t   repair_code   repair misspelling in source code"
  echo -e "\t   open          open repair misspelling execution log file"
  echo -e "\t   validate      validate spellcheck repair results"
  exit 1
}

unset -v REPAIR_DIR REPAIR_EXCLUDE_DIR REPAIR_COMMAND

while getopts "d:e:c:" opt; do
  case "$opt" in
  d) REPAIR_DIR="$OPTARG" ;;
  e) REPAIR_EXCLUDE_DIR="$OPTARG" ;;
  c) REPAIR_COMMAND="$OPTARG" ;;
  ?) help ;;
  esac
done

if [ -z "${REPAIR_DIR}" ] || [ -z "${REPAIR_COMMAND}" ]; then
  echo_error "[*] spellcheck_repair target directory and command parameter is both required"
  help
elif [ ! -e "${REPAIR_DIR}" ] || [ ! -d "${REPAIR_DIR}" ]; then
  echo_error "[*] spellcheck_repair target directory ${REPAIR_DIR} not found or not a directory"
  exit 1
elif [[ ! "${REPAIR_COMMAND}" =~ (scan|repair_path|repair_code|open|validate|test) ]]; then
  echo_error "[*] spellcheck_repair command is invalid"
  exit 1
fi

if [[ $REPAIR_COMMAND == "test" ]]; then
  TEST_CASE=1
  VANILLA=1
elif [[ $REPAIR_COMMAND == "scan" ]]; then
  TEST_CASE=0
  VANILLA=1
elif [[ $REPAIR_COMMAND == "repair_path" ]]; then
  TEST_CASE=0
  VANILLA=0
elif [[ $REPAIR_COMMAND == "repair_code" ]]; then
  TEST_CASE=0
  VANILLA=0
elif [[ $REPAIR_COMMAND == "validate" ]]; then
  TEST_CASE=0
  VANILLA=0
else
  TEST_CASE=0
  VANILLA=1
fi

if [[ ${TEST_CASE} -eq 1 ]]; then
  echo "[*] RUNNING TEST CASES"
  BASE_DIR="./tests"
else
  BASE_DIR="."
fi

SOURCE_CODE_DIR=${REPAIR_DIR}

EXCLUDE_DIR=$(dirname ${SOURCE_CODE_DIR})"/Pods"
if [[ -n "${REPAIR_EXCLUDE_DIR}" ]]; then
  EXCLUDE_DIR="${REPAIR_EXCLUDE_DIR}"
  
  if [ ! -e "${EXCLUDE_DIR}" ] || [ ! -d "${EXCLUDE_DIR}" ]; then
    echo_error "[*] spellcheck_repair exlcude directory ${EXCLUDE_DIR} not found or not a directory"
    exit 1
  fi
else
  EXCLUDE_DIR=$(dirname ${SOURCE_CODE_DIR})"/Pods"
fi

TMP_DIR="${BASE_DIR}/spellcheck"
SPELLCHECK_ERROR_LIST_FILE="${BASE_DIR}/spellcheck_error.txt"
SPELLCHECK_MAPPING_FILE="${BASE_DIR}/spellcheck_mapping.csv"
SPELLCHECK_EXEC_LOG_FILE="${TMP_DIR}/spellcheck_exec.log"
SPELLCHECK_SCAN_REGEXP="^[A-Za-z]"

if [[ ! -e "${SPELLCHECK_ERROR_LIST_FILE}" ]]; then
  echo_error "[*] ${SPELLCHECK_ERROR_LIST_FILE} is required."
  exit 1
fi

if [[ ! -e "${SPELLCHECK_MAPPING_FILE}" ]]; then
  echo_error "[*] ${SPELLCHECK_MAPPING_FILE} is required."
  exit 1
fi

# 打开 SPELLCHECK_EXEC_LOG_FILE 文件
if [[ $REPAIR_COMMAND == "open_logfile" ]]; then
  $(which subl > /dev/null) && {
    subl "$SPELLCHECK_EXEC_LOG_FILE"
    exit 0
  }
  
  $(which code > /dev/null) && {
    code "$SPELLCHECK_EXEC_LOG_FILE"
    exit 0
  }
  
  open "$SPELLCHECK_EXEC_LOG_FILE"
  exit 0
fi

if [[ ${VANILLA} -eq 1 ]] || [[ ${TEST_CASE} -eq 1 ]]; then
  echo "[*] REMOVE SPELLCHECK TEMP DIRECTORY"
  rm -rf "${TMP_DIR}" 2>/dev/null
  rm -f "$SPELLCHECK_EXEC_LOG_FILE" 2>/dev/null
fi

if [[ ! -d "${TMP_DIR}" ]]; then
  mkdir -p "${TMP_DIR}"
fi

if [[ ${TEST_CASE} -eq 1 ]]; then
  cp -r "${BASE_DIR}/Module" "${TMP_DIR}/Module"
  SOURCE_CODE_DIR="${TMP_DIR}/Module"
fi

#################################################

# 准备 folder 文件列表
function prepare_folder_name_list() {
  if [[ ! -e "${TMP_DIR}/folder_name_list.txt" ]]; then
    fd -t d . "${SOURCE_CODE_DIR}" | sort -nr > "${TMP_DIR}/folder_name_list.txt"
  fi
}

# 修复目录名错误, 60s
function scan_folder_name_misspelling() {
  echo "### [BEGIN] SCAN FOLDER NAME MISSPELLING ###" | tee -a "$SPELLCHECK_EXEC_LOG_FILE"
  
  cat "${SPELLCHECK_ERROR_LIST_FILE}" | cut -d',' -f1 | sort | uniq | while IFS= read -r word; do
    if [[ $word =~ ^(#|$) ]]; then
      continue
    fi
    
    word_fixed=$(q "SELECT c2 FROM ${SPELLCHECK_MAPPING_FILE} WHERE c1 = '"${word}"' limit 1" -d ',')
    
    if [[ $word =~ ^[A-Z] ]]; then
      token_regexp="/([^/]*)$word([^a-z/][^/]*)?/$"
      replace_regexp="/\1$word_fixed\2/" # FIXME
    else
      token_regexp="/([^/]*[^a-z])?$word([^a-z/][^/]*)?/$" 
      replace_regexp="/\1$word_fixed\2/"
    fi
    
    rg "${token_regexp}" "${TMP_DIR}/folder_name_list.txt" | grep -v imageset | while read -r folder; do 
      if [[ -z "${word_fixed}" ]]; then
        continue
      fi
      
      folder_fixed=$(echo "${folder}" | perl -pe "s#$token_regexp#$replace_regexp#")
      echo "${word}" >> "${TMP_DIR}/spellcheck_error_import.log"
      echo_error "[*] FOLDER NAME MISSPELLING: ${folder} -> ${folder_fixed}"

      if [[ $(echo "$folder" | tr '[:upper:]' '[:lower:]') == $(echo "$folder_fixed" | tr '[:upper:]' '[:lower:]') ]]; then
        # remove last slash
        if [[ $folder =~ /$ ]]; then
          folder=${folder%?}
        fi
        if [[ $folder_fixed =~ /$ ]]; then
          folder_fixed=${folder_fixed%?}
        fi

        # git mv 中间目录，解决大小写错误修正问题
        echo "git mv ${folder} ${folder_fixed}_camelcase" >> "$SPELLCHECK_EXEC_LOG_FILE"
        echo "git mv ${folder_fixed}_camelcase ${folder_fixed}" >> "$SPELLCHECK_EXEC_LOG_FILE"
      else
        echo "mv ${folder} ${folder_fixed}" >> "$SPELLCHECK_EXEC_LOG_FILE"
      fi
    done
    
    if [[ $word =~ ^[A-Z] ]]; then
      token_regexp="$word([^a-z]|$)"
      replace_regexp="$word_fixed\1"
    else
      token_regexp="([^a-z])$word([^a-z]|$)"
      replace_regexp="\1$word_fixed\2"
    fi 
    
    rg "${token_regexp}" -g "BUILD" -g "Podfile" -g "*.podspec" -g "*.bzl" -g "*.bazel" --files-with-matches "${SOURCE_CODE_DIR}" | while read -r file; do
      if [[ -z "${word_fixed}" ]]; then
        continue
      fi
      
      echo "perl -i -pe \"s/$token_regexp/$replace_regexp/g\" $file" | tee -a "$SPELLCHECK_EXEC_LOG_FILE"
    done
    
    rg "${token_regexp}" -g "*.pbxproj" -g "Podfile" -g "*.podspec" --files-with-matches "${BASE_DIR}" | while read -r file; do
      if [[ -z "${word_fixed}" ]]; then
        continue
      fi
      
      echo "perl -i -pe \"s/$token_regexp/$replace_regexp/g\" $file" | tee -a "$SPELLCHECK_EXEC_LOG_FILE"
    done
  done
  
  echo "### [END] SCAN FOLDER NAME MISSPELLING ###" | tee -a "$SPELLCHECK_EXEC_LOG_FILE"
}

# 准备 file 文件列表
function prepare_file_name_list() {
  if [[ ! -e "${TMP_DIR}/file_name_list.txt" ]]; then
    fd -t f . "${SOURCE_CODE_DIR}" > "${TMP_DIR}/file_name_list.txt"
  fi
}

# 修复文件名错误, 120s
function scan_file_name_misspelling() {
  echo "### [BEGIN] SCAN FILE NAME MISSPELLING ###" | tee -a "$SPELLCHECK_EXEC_LOG_FILE"
  
  cat "${SPELLCHECK_ERROR_LIST_FILE}" | cut -d',' -f1 | sort | uniq | while IFS= read -r word; do
    if [[ $word =~ ^(#|$) ]]; then
      continue
    fi
    
    if [[ $word =~ ^[A-Z] ]]; then
      token_regexp="/([^/]*)$word([^a-z/][^/]*)?$"
    else
      token_regexp="/([^/]*[^a-z])?$word([^a-z/][^/]*)?$" 
    fi
    
    rg "${token_regexp}" "${TMP_DIR}/file_name_list.txt" | grep -v imageset | grep -v pbobjc | while read -r file; do
      word_fixed=$(q "SELECT c2 FROM ${SPELLCHECK_MAPPING_FILE} WHERE c1 = '"${word}"' limit 1" -d ',' 2>/dev/null)
      if [[ -z "${word_fixed}" ]]; then
        continue
      fi

      basename_orig=$(basename "${file}")
      dirname_orig=$(dirname "${file}")
      file_fixed="${dirname_orig}/${basename_orig//$word/$word_fixed}"
      
      if [[ $word =~ ^[A-Z] ]]; then
        replace_regexp="$word_fixed\3"
      else
        replace_regexp="\3$word_fixed\4"
      fi
      
      echo "${word}" >> "${TMP_DIR}/spellcheck_error_import.log"
      echo_error "[*] FILE NAME MISSPELLING: ${file} -> ${file_fixed}"
      
      git -C ${dirname_orig} rev-parse 2>/dev/null
      if [[ $? == 0 ]]; then
        echo "git mv ${file} ${file_fixed}" >> "$SPELLCHECK_EXEC_LOG_FILE"
      else
        echo "mv ${file} ${file_fixed}" >> "$SPELLCHECK_EXEC_LOG_FILE"
      fi
    done
  done 

  echo "### [END] SCAN FILE NAME MISSPELLING ###" | tee -a "$SPELLCHECK_EXEC_LOG_FILE"
}

function check_if_misspelling_in_path() {
  folder_name_misspelling=$(sed -n "/### \[BEGIN\] SCAN FOLDER NAME MISSPELLING ###/,/### \[END\] SCAN FOLDER NAME MISSPELLING ###/p" "${SPELLCHECK_EXEC_LOG_FILE}")
  file_name_misspelling=$(sed -n "/### \[BEGIN\] SCAN FILE NAME MISSPELLING ###/,/### \[END\] SCAN FILE NAME MISSPELLING ###/p" "${SPELLCHECK_EXEC_LOG_FILE}")
  if [[ "${folder_name_misspelling}" =~ mv ]] || [[ "${file_name_misspelling}" =~ mv ]]; then
    echo_success "[*] MISSPELLING FOUND IN PATH NAMING. PLEASE REPAIR PATH NAMING MISSPELLING BY THE FOLLOWING COMMAND:"
    if [[ -e "${EXCLUDE_DIR}" ]] && [[ -d "${EXCLUDE_DIR}" ]]; then
      echo_success "[*] $0 -d ${REPAIR_DIR} -e ${EXCLUDE_DIR} -c repair_path"
    else
      echo_success "[*] $0 -d ${REPAIR_DIR} -c repair_path"
    fi
    PROMPT=$'\e[31m[*] CONTINUE TO REPAIR? [Y/N]: \e[m'; read -r -p "$PROMPT" response
    if [[ "$response" =~ ^([yY][eE][sS]|[yY])$ ]]; then
      if [[ -e "${EXCLUDE_DIR}" ]] && [[ -d "${EXCLUDE_DIR}" ]]; then
        $0 -d ${REPAIR_DIR} -e ${EXCLUDE_DIR} -c repair_path
      else
        $0 -d ${REPAIR_DIR} -c repair_path
      fi
    elif [[ "$response" =~ ^([nN][oO]|[nN])$ ]]; then
      PROMPT2=$'\e[31m[*] CONTINUE TO SCAN SOURCE CODE MISSPELLING? [Y/N]: \e[m'; read -r -p "$PROMPT2" response2
      if [[ "$response2" =~ ^([nN][oO]|[nN])$ ]]; then
      	exit 0
	    fi
    fi
  fi
}

function repair_path() {
  if [[ ! -e "${SPELLCHECK_EXEC_LOG_FILE}" ]]; then
    echo_error "[*] ${SPELLCHECK_EXEC_LOG_FILE} is not found."
    exit 1
  fi
  
  rm -f "${TMP_DIR}/folder_name_list.txt" 2>/dev/null 
  prepare_folder_name_list
  
  rm -f "$SPELLCHECK_EXEC_LOG_FILE" 2>/dev/null
  scan_folder_name_misspelling
  sed -n "/### \[BEGIN\] SCAN FOLDER NAME MISSPELLING ###/,/### \[END\] SCAN FOLDER NAME MISSPELLING ###/p" "${SPELLCHECK_EXEC_LOG_FILE}" | sh
  
  rm -f "${TMP_DIR}/file_name_list.txt" 2>/dev/null 
  prepare_file_name_list
  
  rm -f "$SPELLCHECK_EXEC_LOG_FILE" 2>/dev/null
  scan_file_name_misspelling
  sed -n "/### \[BEGIN\] SCAN FILE NAME MISSPELLING ###/,/### \[END\] SCAN FILE NAME MISSPELLING ###/p" "${SPELLCHECK_EXEC_LOG_FILE}" | sh
  
  if [[ -n $(git status -uno -s) && $TEST_CASE -eq 0 ]]; then
    git add ${BASE_DIR}/Podfile
    git add ${BASE_DIR}/\*.podspec
    git add ${BASE_DIR}/\*.pbxproj
    git add ${SOURCE_CODE_DIR}/*
    git commit -m "[FIX] spellcheck repair: path naming misspelling"
  fi
  
  rm -f "$SPELLCHECK_EXEC_LOG_FILE" 2>/dev/null
  scan_source_code_import_misspelling
  sed -n "/### \[BEGIN\] SCAN SOURCE CODE IMPORT MISSPELLING ###/,/### \[END\] SCAN SOURCE CODE IMPORT MISSPELLING ###/p" "${SPELLCHECK_EXEC_LOG_FILE}" | sh
 
  if [[ -n $(git status -uno -s) && $TEST_CASE -eq 0 ]]; then
    git add ${SOURCE_CODE_DIR}/*
    git commit -m "[FIX] spellcheck repair: import misspelling"
  fi
}

function scan_source_code_import_misspelling() {
  echo "### [BEGIN] SCAN SOURCE CODE IMPORT MISSPELLING ###" | tee -a "$SPELLCHECK_EXEC_LOG_FILE"
  
  if [[ -e "${TMP_DIR}/spellcheck_error_import.log" ]]; then
    cat "${TMP_DIR}/spellcheck_error_import.log" | sort | uniq | while IFS= read -r word; do
      if [[ $word =~ ^(#|$) ]]; then
        continue
      fi

      word_fixed=$(q "SELECT c2 FROM ${SPELLCHECK_MAPPING_FILE} WHERE c1 = '"${word}"' limit 1" -d ',' 2>/dev/null)
      if [[ -z $word_fixed ]]; then
        continue
      fi

      if [[ $word =~ ^[A-Z] ]]; then
        token_regexp="$word([^a-z]|$)"
        replace_regexp="$word_fixed\1"
        file_name="${TMP_DIR}/exclude/${word}_uppercase.txt"
        exclude_file="${TMP_DIR}/exclude/${word}_uppercase_exclude.txt"
      else
        token_regexp="([^a-z])$word([^a-z]|$)" 
        replace_regexp="\1$word_fixed\2"
        file_name="${TMP_DIR}/exclude/${word}_lowercase.txt"
        exclude_file="${TMP_DIR}/exclude/${word}_lowercase_exclude.txt"
      fi 

      echo "# $word" | tee -a "$SPELLCHECK_EXEC_LOG_FILE"
      rg "${token_regexp}" --pcre2 --type objc --type objcpp --type swift --files-with-matches "${SOURCE_CODE_DIR}" | while read -r file; do

        if [[ $file =~ (pbobjc|ApiModel)\.[hm]$ ]] || [[ $file =~ /.*\/Example\/.*/ ]]; then
          continue
        fi

        if [[ -e $exclude_file ]]; then
          exclude_line=$(rg -n -w -f "${exclude_file}" "${file}" | cut -d: -f1 | perl -pe 's/(\d+)/\1..\1 or /g' | perl -pe 's/\r?\n//g')
        else
          exclude_line=""
        fi
        
        # TODO 输出 exlcude 地方，便于后续修复
        
        if [[ "$file" =~ swift$ ]]; then
          echo "perl -i -pe \"${exclude_line}s/$token_regexp/$replace_regexp/g if /^\s*import\s+/\" $file" | tee -a "$SPELLCHECK_EXEC_LOG_FILE"
        else 
          echo "perl -i -pe \"${exclude_line}s/$token_regexp/$replace_regexp/g if /^\s*#import\s+/\" $file" | tee -a "$SPELLCHECK_EXEC_LOG_FILE"
        fi
      done
    done
  fi
  
  echo "### [END] SCAN SOURCE CODE IMPORT MISSPELLING ###" | tee -a "$SPELLCHECK_EXEC_LOG_FILE"
}

############################### 以上是目录和文件名处理的部分 #######################################

# 准备 exclude 目录头文件，例如 Pods 目录头文件，pbobjc, ApiModel 等 IDL 自动生成的文件
function prepare_path_exclude_header_file() {
  echo "### [BEGIN] PREPARE PATH EXCLUDE HEADER FILE ###" | tee -a "$SPELLCHECK_EXEC_LOG_FILE"
  if [[ ! -e "${TMP_DIR}/exclude_header_files.txt" ]]; then
    touch "${TMP_DIR}/exclude_header_files.txt"
  fi
  
  if [[ -e "${EXCLUDE_DIR}" ]] && [[ -d "${EXCLUDE_DIR}" ]]; then
    fd -L -e h -t f . "${EXCLUDE_DIR}" --exec echo {/.} >> "${TMP_DIR}/exclude_header_files.txt"
  fi
  fd -s -e h -t f "(pbobjc|ApiModel)" "${SOURCE_CODE_DIR}" --exec echo {/.} >> "${TMP_DIR}/exclude_header_files.txt"
  
  if [[ -e "${TMP_DIR}/exclude_header_files.txt" ]]; then
    cat "${TMP_DIR}/exclude_header_files.txt" \
    | perl -pe 's/^\/\/(\\(.|\r?\n)|[^\\\n])*//g' \
    | perl -pe 's/^[ \s\t]*(\/\/|\/\*|\*)(\\(.|\r?\n)|[^\\\n])*//g' \
    | perl -pe 's/^[ \s\t]*\*.*$//g' > "${TMP_DIR}/exclude_header_files_trimmed.txt"
  fi
  
  echo "### [END] PREPARE PATH EXCLUDE HEADER FILE ###" | tee -a "$SPELLCHECK_EXEC_LOG_FILE"
}

function prepare_exclude_header_file() {
  echo "### [BEGIN] PREPARE EXCLUDE HEADER FILE ###" | tee -a "$SPELLCHECK_EXEC_LOG_FILE"
  if [[ ! -e "${TMP_DIR}/exclude_header_files.txt" ]]; then
    touch "${TMP_DIR}/exclude_header_files.txt"
  fi
    
  if [[ -e "${EXCLUDE_DIR}" ]] && [[ -d "${EXCLUDE_DIR}" ]]; then
    fd -L -e h -t f . "${EXCLUDE_DIR}" --exec echo {/.} >> "${TMP_DIR}/exclude_header_files.txt"
    fd -L -e h -t f . "${EXCLUDE_DIR}" --exec cat {} >> "${TMP_DIR}/exclude_header_files.txt"
  fi
  fd -s -e h -t f "(pbobjc|ApiModel)" "${SOURCE_CODE_DIR}" --exec echo {/.} >> "${TMP_DIR}/exclude_header_files.txt"
  fd -s -e h -t f "(pbobjc|ApiModel)" "${SOURCE_CODE_DIR}" --exec cat {} >> "${TMP_DIR}/exclude_header_files.txt"
  
  if [[ -e "${SOURCE_CODE_DIR}/TTUGCApiGateway" ]]; then
    fd -s -e h -t f . "${SOURCE_CODE_DIR}/TTUGCApiGateway" --exec cat {} >> "${TMP_DIR}/exclude_header_files.txt"
  fi
  
  if [[ -e "${TMP_DIR}/exclude_header_files.txt" ]]; then
    cat "${TMP_DIR}/exclude_header_files.txt" \
    | perl -pe 's/^\/\/(\\(.|\r?\n)|[^\\\n])*//g' \
    | perl -pe 's/^[ \s\t]*(\/\/|\/\*|\*)(\\(.|\r?\n)|[^\\\n])*//g' \
    | perl -pe 's/^[ \s\t]*\*.*$//g' > "${TMP_DIR}/exclude_header_files_trimmed.txt"
  fi
  
  echo "### [END] PREPARE EXCLUDE HEADER FILE ###" | tee -a "$SPELLCHECK_EXEC_LOG_FILE"
}

# 扫描 exclude 目录头文件错误 Token 对应行, 60s
function extract_line_from_exclude_header_file() {
  echo "### [BEGIN] EXCLUDE HEADER FILE ###" | tee -a "$SPELLCHECK_EXEC_LOG_FILE"
  
  if [[ ! -e "${TMP_DIR}/exclude_header_files_trimmed.txt" ]]; then
    prepare_path_exclude_header_file
  fi
  
  mkdir -p "${TMP_DIR}/exclude"
  while IFS= read -r line; do
    if [[ $line =~ ^(#|$) ]]; then
      continue
    fi
    
    word=$(echo "${line}" | cut -d',' -f1)
    
    if [[ $word =~ ^[A-Z] ]]; then
      token_regexp="$word([^a-z]|$)"
      file_name="${TMP_DIR}/exclude/${word}_uppercase.txt"
    else
      token_regexp="([^a-z])$word([^a-z]|$)"
      file_name="${TMP_DIR}/exclude/${word}_lowercase.txt"
    fi
    
    if [[ ! $word =~ ${SPELLCHECK_SCAN_REGEXP} && ${TEST_CASE} -eq 0 ]]; then
      continue
    fi
    
    exclude_tokens=$(LC_ALL=C rg "${token_regexp}" "${TMP_DIR}/exclude_header_files_trimmed.txt")
    if [[ $? == 0 ]]; then
      echo "${exclude_tokens}" | sort > "${file_name}"
    fi
  done < "${SPELLCHECK_ERROR_LIST_FILE}"
  
  echo "### [END] EXCLUDE HEADER FILE ###" | tee -a "$SPELLCHECK_EXEC_LOG_FILE"
}

# 提取 exclude 目录头文件错误行里的 Token
function extract_exclude_tokens_from_exclude_header_line() {
  echo "### [BEGIN] EXTRACT EXCLUDE TOKENS ###" | tee -a "$SPELLCHECK_EXEC_LOG_FILE"

  fd -t f "(uppercase|lowercase).txt" "${TMP_DIR}/exclude" --exec echo {/.} | while read -r filename; do 
    word=$(echo "${filename}" | perl -pe 's/_lowercase|_uppercase//g')
    
    if [[ $word =~ ^[A-Z] ]]; then
      token_regexp="$word([^a-z]|$)"
    else
      token_regexp="(^|[^a-z])$word([^a-z]|$)"
    fi
    
    cat "${TMP_DIR}/exclude/${filename}.txt" \
    | perl -pe 's/^\/\/(\\(.|\r?\n)|[^\\\n])*//g' \
    | perl -pe 's/^[ \s\t]*(\/\/|\/\*|\*)(\\(.|\r?\n)|[^\\\n])*//g' \
    | perl -pe 's/^[ \s\t]*\*.*$//g' \
    | perl -pe 's/@"[^"]+"//g' \
    | perl -pe 's/@"[0-9a-zA-Z\,\:\;\/\\\.\_\-\=\+]{50,}"//g' \
    | perl -pe 's/^\.\/\/.*\.(h|m|mm)$//g' \
    | perl -pe 's/@"(0x|#)?([a-zA-Z0-9]{6}|[a-zA-Z0-9]{8})"//g' \
    | perl -pe 's/[\[\]\;\*\^\=\+\-\"\%\@\!\<\>\(\)\{\}\,\:\.\/\\\&'\'']/ /g' \
    | perl -pe 's/(\.)/\
    /g' \
    | perl -pe 's/ /
    /g' \
    | perl -pe 's/^[[:space:]]*$//g' \
    | perl -pe 's/[[:blank:]]*//g' \
    | sort \
    | uniq \
    | grep -E "${token_regexp}" \
    > "${TMP_DIR}/exclude/${filename}_exclude.txt"
  done
  
  echo "### [END] EXTRACT EXCLUDE TOKENS ###" | tee -a "$SPELLCHECK_EXEC_LOG_FILE"
}

# 修复源代码错误
function scan_source_code_misspelling() {
  FLAG_SCAN_QUOTE=$1 || 0
  
  if [[ $FLAG_SCAN_QUOTE -eq 1 ]]; then
    echo "### [BEGIN] SOURCE CODE IN QUOTE MISSPELLING REPAIR ###" | tee -a "$SPELLCHECK_EXEC_LOG_FILE"
  else
    echo "### [BEGIN] SOURCE CODE MISSPELLING REPAIR ###" | tee -a "$SPELLCHECK_EXEC_LOG_FILE"
  fi
  
  while IFS= read -r line; do
    if [[ $line =~ ^# || $line =~ ^[\s\t]*$ ]]; then
      continue
    fi
    
    word=$(echo "${line}" | cut -d',' -f1)
    token=$(echo "${line}" | cut -d',' -f2) # 判断 word 跟 token 一样的情况

    if [[ ! $word =~ ${SPELLCHECK_SCAN_REGEXP} && ${TEST_CASE} -eq 0 ]]; then
      continue
    fi
    
    word_fixed=$(q "SELECT c2 FROM ${SPELLCHECK_MAPPING_FILE} WHERE c1 = '"${word}"' limit 1" -d ',' 2>/dev/null)
    if [[ -z $word_fixed ]]; then
      continue
    fi
      
    exclude_file1=""
    exclude_file2=""
    
    if [[ $word =~ ^[A-Z] ]]; then
      token_regexp="$word([^a-z\"]|$)"
      replace_regexp="$word_fixed\1"
      file_name="${TMP_DIR}/exclude/${word}_uppercase.txt"
      exclude_file1="${TMP_DIR}/exclude/${word}_uppercase_exclude.txt"
    else
      token_regexp="([^a-z]|^)$word([^a-z\"]|$)"
      replace_regexp="\1$word_fixed\2"
      file_name="${TMP_DIR}/exclude/${word}_lowercase.txt"
      exclude_file1="${TMP_DIR}/exclude/${word}_lowercase_exclude.txt"
    fi
      
    # 取消注释，用于批量导出 "" 内容，供手动消费，rg 命令不能直接过滤 ""
    if [[ $FLAG_SCAN_QUOTE -eq 1 ]]; then
      if [[ $word =~ ^[A-Z] ]]; then
        token_regexp="$word([^a-z]|$)"
        replace_regexp="$word_fixed\1"
      else
        token_regexp="([^a-z]|^)$word([^a-z]|$)"
        replace_regexp="\1$word_fixed\2"
      fi
    fi
    
    # 保存原始值
    orig_word=${word}
    orig_word_fixed=${word_fixed}
    
    if [[ -n "${last_word}" ]] && [[ -n "${last_word_fixed}" ]] && [[ "${last_word}" != "${orig_word}" ]]; then
      # 注释，用于批量导出 "" 内容供手动消费
      if [[ $FLAG_SCAN_QUOTE -eq 0 && $TEST_CASE -eq 0 ]]; then
        echo "if [[ -n \$(git status -uno -s) ]]; then git add ${SOURCE_CODE_DIR}/*; fi" >> "$SPELLCHECK_EXEC_LOG_FILE"
        echo "if [[ -n \$(git status -uno -s) ]]; then git commit -m \"[FIX] spellcheck repair: $last_word -> $last_word_fixed\"; fi" >> "$SPELLCHECK_EXEC_LOG_FILE"
      fi
    fi
        
    search_regexp=${token_regexp}
    if [[ -n "${token}" ]] && [[ "${token}" != "${word}" ]]; then
      search_regexp=${token}
      word_fixed=$(echo "${token}" | perl -pe "s/${word}/${word_fixed}/g")
      word=${token}
      if [[ $word =~ ^[A-Z] ]]; then
        exclude_file2="${TMP_DIR}/exclude/${word}_uppercase_exclude.txt"
      else
        exclude_file2="${TMP_DIR}/exclude/${word}_lowercase_exclude.txt"
      fi
    fi
    
    echo "# $orig_word in ${search_regexp}" | tee -a "$SPELLCHECK_EXEC_LOG_FILE"
    rg "${search_regexp}" --pcre2 --type objc --type objcpp --type swift --files-with-matches "${SOURCE_CODE_DIR}" | while read -r file; do
      
      if [[ $file =~ (pbobjc|ApiModel)\.[hm]$ ]] || [[ $file =~ /.*\/Example\/.*/ ]]; then
        continue
      fi
      
      if [[ $word =~ ^[A-Z] ]]; then
        token_regexp='(?!\"[\w\s\.:_-]*[\\"]*[\w\s\.:_-]*)'"$word([^a-z\"]|$)"'(?![\w\s\.:_-]*[\\"]*[\w\s\.:_-]*\")'
        replace_regexp="$word_fixed\1"
      else
        token_regexp='(?!\"[\w\s\.:_-]*[\\"]*[\w\s\.:_-]*)'"([^a-z]|^)$word([^a-z\"]|$)"'(?![\w\s\.:_-]*[\\"]*[\w\s\.:_-]*\")'
        replace_regexp="\1$word_fixed\2"
      fi
      
      # 取消注释，用于批量导出 "" 内容，供手动消费
      if [[ $FLAG_SCAN_QUOTE -eq 1 ]]; then
        if [[ $word =~ ^[A-Z] ]]; then
          token_regexp="$word([^a-z]|$)"
          replace_regexp="$word_fixed\1"
        else
          token_regexp="([^a-z]|^)$word([^a-z]|$)"
          replace_regexp="\1$word_fixed\2"
        fi
      fi
      
      
      local exclude_line=""
      local exclude_token_matchings=""
      for exclude_file in $exclude_file1 $exclude_file2; do
        if [[ -e $exclude_file ]]; then
          while IFS= read -r exclude_token; do
            if [[ $exclude_token =~ ^[\s\t]*$ ]]; then
              continue
            fi
            
            local local_variable="_${exclude_token}"
            local setter_method="set"`echo ${exclude_token:0:1} | tr '[a-z]' '[A-Z]'`${exclude_token:1}
            local getter_method="get"`echo ${exclude_token:0:1} | tr '[a-z]' '[A-Z]'`${exclude_token:1}
            
            # 只过滤 -w，例如 exclude_token: Foo 不过滤 FooTrue，认为不一样的 token
            # 更新：token 模式下，过滤 token 存在的 exlcude_file
            exclude_token_matchings+=$(rg -w --only-matching "(${exclude_token}|${setter_method}|${getter_method})" "${file}" | sort | uniq | perl -pe 's/\r?\n/ /g')
            exclude_token_matchings+=$(rg -w --only-matching "(${local_variable})" "${file}" | sort | uniq | perl -pe 's/\r?\n/ /g')
            
            line_numbers=$(rg -n -w "(${exclude_token}|${local_variable}|${setter_method}|${getter_method})" "${file}" | cut -d: -f1)
            exclude_line+=$(echo $line_numbers | perl -pe 's/(\d+)/\1..\1 or /g' | perl -pe 's/\r?\n//g')
            if [[ -n "${line_numbers}" ]]; then
              line_print+=$(echo $line_numbers | perl -pe 's/(\d+)/\1p;/g' | perl -pe 's/\r?\n//g')
              sed -n "${line_print}" "${file}" | rg -w --only-matching "(${exclude_token}|${local_variable}|${setter_method}|${getter_method})" >> "${TMP_DIR}/exclude_tokens.txt"
            fi
          done < "${exclude_file}"
        fi 
      done 
      
      local matching_index=1
      matchings=(${exclude_token_matchings})
      for matching in "${matchings[@]}"; do
        if [[ $matching =~ ^# || $matching =~ ^[\s\t]*$ || $matching =~ ^\r\n$ ]]; then
          continue
        fi
        matching_reversed=$(echo "${matching}" | awk -v matching_index="${matching_index}" '{print "\\b" $1 "\\b" "#" "___" matching_index "___"}')
        matching_index=$((matching_index + 1))
        echo "perl -i -pe 's#$matching_reversed#g' $file" | tee -a "$SPELLCHECK_EXEC_LOG_FILE"
      done
      
      echo "perl -i -pe 's/$token_regexp/$replace_regexp/g' $file" | tee -a "$SPELLCHECK_EXEC_LOG_FILE"
      
      local matching_index=1
      for matching in "${matchings[@]}"; do
        if [[ $matching =~ ^# || $matching =~ ^[\s\t]*$ ]]; then
          continue
        fi
        matching_reversed=$(echo "${matching}" | awk -v matching_index="${matching_index}" '{print "___" matching_index "___" "#" $1}')
        matching_index=$((matching_index + 1))
        echo "perl -i -pe 's#$matching_reversed#g' $file" | tee -a "$SPELLCHECK_EXEC_LOG_FILE"
      done
      # echo "perl -i -pe '${exclude_line}s/$token_regexp/$replace_regexp/g' $file" | tee -a "$SPELLCHECK_EXEC_LOG_FILE"
    done
    
    last_word=${orig_word}
    last_word_fixed=${orig_word_fixed}
  done < "${SPELLCHECK_ERROR_LIST_FILE}" 
            
  # 注释，用于批量导出 "" 内容供手动消费
  if [[ $FLAG_SCAN_QUOTE -eq 0 && $TEST_CASE -eq 0 ]]; then
    echo "if [[ -n \$(git status -uno -s) ]]; then git add ${SOURCE_CODE_DIR}/*; fi" >> "$SPELLCHECK_EXEC_LOG_FILE"
    echo "if [[ -n \$(git status -uno -s) ]]; then git commit -m \"[FIX] spellcheck repair: $last_word -> $last_word_fixed\"; fi" >> "$SPELLCHECK_EXEC_LOG_FILE"
  fi 
  
  if [[ -e "${TMP_DIR}/exclude_tokens.txt" ]]; then
    sort "${TMP_DIR}/exclude_tokens.txt" | uniq > "${TMP_DIR}/exclude_tokens.tmp.txt" && mv "${TMP_DIR}/exclude_tokens.tmp.txt" "${TMP_DIR}/exclude_tokens.txt"
  fi
  
  if [[ $FLAG_SCAN_QUOTE -eq 1 ]]; then
    echo "### [END] SOURCE CODE IN QUOTE MISSPELLING REPAIR ###" | tee -a "$SPELLCHECK_EXEC_LOG_FILE"
  else
    echo "### [END] SOURCE CODE MISSPELLING REPAIR ###" | tee -a "$SPELLCHECK_EXEC_LOG_FILE"
  fi
}

###################################################################################

function check_if_misspelling_in_source_code() {
  source_code_misspelling=$(sed -n "/### \[BEGIN\] SOURCE CODE MISSPELLING REPAIR ###/,/### \[END\] SOURCE CODE MISSPELLING REPAIR ###/p" "${SPELLCHECK_EXEC_LOG_FILE}")
  source_code_in_quote_misspelling=$(sed -n "/### \[BEGIN\] SOURCE CODE IN QUOTE MISSPELLING REPAIR ###/,/### \[END\] SOURCE CODE IN QUOTE MISSPELLING REPAIR ###/p" "${SPELLCHECK_EXEC_LOG_FILE}")
  if [[ "${source_code_misspelling}" =~ perl ]] || [[ "${source_code_in_quote_misspelling}" =~ perl ]]; then
    echo_success "[*] MISSPELLING FOUND IN SOURCE CODE. PLEASE REPAIR SOURCE CODE MISSPELLING BY THE FOLLOWING COMMAND:"
    if [[ -e "${EXCLUDE_DIR}" ]] && [[ -d "${EXCLUDE_DIR}" ]]; then
      echo_success "[*] $0 -d ${REPAIR_DIR} -e ${EXCLUDE_DIR} -c repair_code"
    else
      echo_success "[*] $0 -d ${REPAIR_DIR} -c repair_code"
    fi
    PROMPT=$'\e[31m[*] CONTINUE TO REPAIR? [Y/N]: \e[m'; read -r -p "$PROMPT" response
    if [[ "$response" =~ ^([yY][eE][sS]|[yY])$ ]]; then
      if [[ -e "${EXCLUDE_DIR}" ]] && [[ -d "${EXCLUDE_DIR}" ]]; then
        $0 -d ${REPAIR_DIR} -e ${EXCLUDE_DIR} -c repair_code
      else
        $0 -d ${REPAIR_DIR} -c repair_code
      fi
    else
      exit 0
    fi
  else
    echo_success "[*] GOOD JOB, NO MISSPELLING FOUND."
  fi
}

function repair_code() {
  if [[ ! -e "${SPELLCHECK_EXEC_LOG_FILE}" ]]; then
    echo_error "[*] ${SPELLCHECK_EXEC_LOG_FILE} not found."
    exit 1
  fi
  
  sed -n "/### \[BEGIN\] SOURCE CODE MISSPELLING REPAIR ###/,/### \[END\] SOURCE CODE MISSPELLING REPAIR ###/p" "${SPELLCHECK_EXEC_LOG_FILE}" | sh
  sed -n "/### \[BEGIN\] SOURCE CODE IN QUOTE MISSPELLING REPAIR ###/,/### \[END\] SOURCE CODE IN QUOTE MISSPELLING REPAIR ###/p" "${SPELLCHECK_EXEC_LOG_FILE}" | sh
}

###################################################################################

function prepare_exclude_string_file() {
  rm -f "${TMP_DIR}/exclude_string_files.txt"
  if [[ ! -e "${TMP_DIR}/exclude_string_files.txt" ]] && [[ -e ${EXCLUDE_DIR} ]]; then
    touch "${TMP_DIR}/exclude_string_files.txt"
    fd -L -e m -e mm -t f . "${EXCLUDE_DIR}" --exec cat {} | rg --only-matching --pcre2 '(?<=@")[^"]+(?=")' \
    | perl -pe 's/^\/\/(\\(.|\r?\n)|[^\\\n])*//g' \
    | perl -pe 's/^[ \s\t]*(\/\/|\/\*|\*)(\\(.|\r?\n)|[^\\\n])*//g' \
    | perl -pe 's/^[ \s\t]*\*.*$//g' \
    | perl -pe 's/@"[^"]+"//g' \
    | perl -pe 's/@"[0-9a-zA-Z\,\:\;\/\\\.\_\-\=\+]{50,}"//g' \
    | perl -pe 's/^\.\/\/.*\.(h|m|mm)$//g' \
    | perl -pe 's/@"(0x|#)?([a-zA-Z0-9]{6}|[a-zA-Z0-9]{8})"//g' \
    | perl -pe 's/[\[\]\;\*\^\=\+\-\"\%\@\!\<\>\(\)\{\}\,\:\.\/\\\&'\'']/ /g' \
    | perl -pe 's/(\.)/\
    /g' \
    | perl -pe 's/ /
    /g' \
    | perl -pe 's/^[[:space:]]*$//g' \
    | perl -pe 's/[[:blank:]]*//g' \
    | sort \
    | uniq >> "${TMP_DIR}/exclude_string_files.txt"
  fi
}

function prepare_source_code_fixed_file() {
  rm -f "${TMP_DIR}/source_code_token_files.txt"
  if [[ ! -e "${TMP_DIR}/source_code_token_files.txt" ]]; then
    touch "${TMP_DIR}/source_code_token_files.txt"
  fi
  
  last_commit_date=$(git --no-pager log -1 --date=unix | grep Date: | cut -d":" -f2 | perl -pe 's/ //g')
  last_commit_name=$(git config --get user.name)
  last_commit_id=$(git --no-pager log -g --oneline --author="${last_commit_name}" --since=$(date -r $(( ${last_commit_date} - 1209600 )) +%s) | tail -1 | cut -d ' ' -f 1)
  
  git diff $last_commit_id.. -U0 | grep '^[-]' | grep -Ev '^(--- a/|\+\+\+ b/)' > "${TMP_DIR}/source_code_token_files.txt"
}

function extract_source_code_tokens() {
  echo "### [BEGIN] EXTRACT SOURCE CODE TOKENS ###" | tee -a "$SPELLCHECK_EXEC_LOG_FILE"
  
  rm -f "${TMP_DIR}/source_code_tokens.txt"
  if [[ ! -e "${TMP_DIR}/source_code_tokens.txt" ]]; then
    touch "${TMP_DIR}/source_code_tokens.txt"
  fi
  
  while IFS= read -r line; do 
    if [[ $line =~ ^(#|$) ]]; then
      continue
    fi
    
    word=$(echo "${line}" | cut -d',' -f1)
    
    if [[ ! $word =~ ${SPELLCHECK_SCAN_REGEXP} && ${TEST_CASE} -eq 0 ]]; then
      continue
    fi
    
    if [[ $word =~ ^[A-Z] ]]; then
      token_regexp="$word([^a-z]|$)"
    else
      token_regexp="(^|[^a-z])$word([^a-z]|$)"
    fi
    
    # echo "# $word" # | tee -a "$SPELLCHECK_EXEC_LOG_FILE"
    rg "${token_regexp}" "${TMP_DIR}/source_code_token_files.txt" \
    | perl -pe 's/^\/\/(\\(.|\r?\n)|[^\\\n])*//g' \
    | perl -pe 's/^[ \s\t]*(\/\/|\/\*|\*)(\\(.|\r?\n)|[^\\\n])*//g' \
    | perl -pe 's/^[ \s\t]*\*.*$//g' \
    | perl -pe 's/@"[0-9a-zA-Z\,\:\;\/\\\.\_\-\=\+]{50,}"//g' \
    | perl -pe 's/^\.\/\/.*\.(h|m|mm)$//g' \
    | perl -pe 's/@"(0x|#)?([a-zA-Z0-9]{6}|[a-zA-Z0-9]{8})"//g' \
    | perl -pe 's/[\[\]\;\*\^\=\+\-\"\%\@\!\<\>\(\)\{\}\,\:\.\/\\\&'\'']/ /g' \
    | perl -pe 's/ /
    /g' \
    | perl -pe 's/^[[:space:]]*$//g' \
    | perl -pe 's/[[:blank:]]*//g' \
    | sort \
    | uniq \
    | grep -E "${token_regexp}" \
    >> "${TMP_DIR}/source_code_tokens.txt"
    
  done < "${SPELLCHECK_ERROR_LIST_FILE}"
  
  echo "### [END] EXTRACT SOURCE CODE TOKENS ###" | tee -a "$SPELLCHECK_EXEC_LOG_FILE"
}

function validate_source_code_tokens() {
  echo "### [BEGIN] VALIDATE SOURCE CODE TOKENS ###" | tee -a "$SPELLCHECK_EXEC_LOG_FILE"
  
  while IFS= read -r word; do
    if [[ $word =~ ^[\s\t]*$ ]]; then
      continue
    fi
    
    rg -w "$word" "${TMP_DIR}/exclude_header_files_trimmed.txt"
  done < "${TMP_DIR}/source_code_tokens.txt"
  
  while IFS= read -r word; do
    if [[ $word =~ ^[\s\t]*$ ]]; then
      continue
    fi
    
    rg -w "$word" "${SOURCE_CODE_DIR}"
  done < "${TMP_DIR}/source_code_tokens.txt"

  while IFS= read -r line; do
    if [[ $line =~ ^# || $line =~ ^[\s\t]*$ ]]; then
      continue
    fi
    
    word=$(echo "${line}" | cut -d',' -f1)
    
    if [[ ! $word =~ ${SPELLCHECK_SCAN_REGEXP} && ${TEST_CASE} -eq 0 ]]; then
      continue
    fi
    
    if [[ $word =~ ^[A-Z] ]]; then
      token_regexp="$word([^a-z]|$)"
    else
      token_regexp="(^|[^a-z])$word([^a-z]|$)"
    fi

    # 检查改动的 selector 是否包含在 source code 里
    rg --only-matching --pcre2 "(?<=@selector\()[^(]*$word[^)]*(?=\))" "${TMP_DIR}/source_code_token_files.txt" | perl -pe 's/:/\n/g' | grep -E "$token_regexp" | while IFS= read -r selector_token; do 
      echo "#selector_token: $selector_token"

      rg "$selector_token" "${SOURCE_CODE_DIR}"
      rg "$selector_token" "${TMP_DIR}/exclude_header_files_trimmed.txt" -q
      
      if [[ $? == 0 ]]; then
        echo "#selector_token: $selector_token"
      fi
    done
    
    # # 检查改动的 @"" 是否包含在 source code 里
    rg --only-matching --pcre2 '(?<=@")[^",]*'"$word"'[^"]*(?=")' "${TMP_DIR}/source_code_token_files.txt" | grep -E "$token_regexp" | while IFS= read -r string_token; do
      echo "#string_token: $string_token"
      
      rg "$string_token" "${SOURCE_CODE_DIR}"
      rg "$string_token" "${TMP_DIR}/exclude_header_files_trimmed.txt" -q
      
      if [[ $? == 0 ]]; then
        echo "#word: $word\n#string_token: $string_token"
      fi
    done
    
  done < "${SPELLCHECK_ERROR_LIST_FILE}"
  
  echo "### [END] VALIDATE SOURCE CODE TOKENS ###" | tee -a "$SPELLCHECK_EXEC_LOG_FILE"
}

# error 区分大小写错误和拼写错误，根据 mapping 文件判断
# git diff -U0 | grep '^[+-]' | grep -Ev '^(--- a/|\+\+\+ b/)'
# git diff ..a47403ecea1cda4d4087113389052855a85a8af7 | grep -E '[-+](\@protocol|\@interface)' | grep -E '^\+' | cut -d ' ' -f 2 | cut -d '(' -f1 | uniq > spellcheck_rename.log
# Compound words: RelationShip -> Relationship, placeHolder -> placeholder, whiteList -> whitelist, ProFile -> Profile
# "" 里的符号，检查 .m/.mm/.swift 文件里的 "" 符号
# TODO: 过滤错误连着实际错误的 case，造成第一次替换无法发现的问题

start=`date +%s`

if [[ $REPAIR_COMMAND == "scan" ]]; then
  prepare_folder_name_list
  scan_folder_name_misspelling

  prepare_file_name_list
  scan_file_name_misspelling
  
  check_if_misspelling_in_path # 检查目录是否存在错误，存在退出路径
  
  prepare_exclude_header_file
  extract_line_from_exclude_header_file
  extract_exclude_tokens_from_exclude_header_line
  
  scan_source_code_import_misspelling
  scan_source_code_misspelling 0
  scan_source_code_misspelling 1 # scan word in quotes
  
  check_if_misspelling_in_source_code # 检查源文件是否存在错误，存在退出路径
fi

if [[ $REPAIR_COMMAND == "validate" ]]; then
  prepare_exclude_string_file
  prepare_source_code_fixed_file
  extract_source_code_tokens
  validate_source_code_tokens
fi

if [[ $REPAIR_COMMAND == "repair_path" ]]; then
  repair_path

  prepare_path_exclude_header_file
  extract_line_from_exclude_header_file
  extract_exclude_tokens_from_exclude_header_line
  scan_source_code_import_misspelling
elif [[ $REPAIR_COMMAND == "repair_code" ]]; then
  repair_code
fi

if [[ $TEST_CASE -eq 1 ]]; then
  prepare_folder_name_list
  scan_folder_name_misspelling

  prepare_file_name_list
  scan_file_name_misspelling
  
  repair_path
  
  prepare_exclude_header_file
  extract_line_from_exclude_header_file
  extract_exclude_tokens_from_exclude_header_line
  
  scan_source_code_misspelling 0
  scan_source_code_misspelling 1 # scan word in quotes
                            
  sh "${SPELLCHECK_EXEC_LOG_FILE}"
  
  diff -q <(find ${TMP_DIR}/Module | perl -pe "s#${TMP_DIR}/Module##") <(find "${BASE_DIR}/Expected" | perl -pe "s#${BASE_DIR}/Expected##") >/dev/null
  if [[ $? -eq 1 ]]; then
    echo_error "[*] TEST CASE RUN FAILED"
    diff <(find ${TMP_DIR}/Module | perl -pe "s#${TMP_DIR}/Module##") <(find "${BASE_DIR}/Expected" | perl -pe "s#${BASE_DIR}/Expected##")
    echo_error "[*] TEST CASE RUN FAILED"
  else
    echo_success "[*] TEST CASE RUN SUCCESS"
  fi
  
  diff -q <(cat "${TMP_DIR}/Module/Bar.h" | perl -pe 's/^\/\/(\\(.|\r?\n)|[^\\\n])*//g' \
    | perl -pe 's/(([ \s\t]*(\/\/|\/\*))|(^[ \s\t]*\*))(\\(.|\r?\n)|[^\\\n])*//g' \
    | perl -pe 's/^[ \s\t]*\*.*$//g') <(cat "${BASE_DIR}/Expected/Bar.h" | perl -pe 's/^\/\/(\\(.|\r?\n)|[^\\\n])*//g' \
    | perl -pe 's/(([ \s\t]*(\/\/|\/\*))|(^[ \s\t]*\*))(\\(.|\r?\n)|[^\\\n])*//g' \
    | perl -pe 's/^[ \s\t]*\*.*$//g') >/dev/null
  if [[ $? -eq 1 ]]; then
    echo_error "[*] TEST CASE RUN FAILED"
    diff "${TMP_DIR}/Module/Bar.h" "${BASE_DIR}/Expected/Bar.h"
    echo_error "[*] TEST CASE RUN FAILED"
  else
    echo_success "[*] TEST CASE RUN SUCCESS"
  fi
fi

end=`date +%s`
runtime=$( echo "$end - $start" | bc -l )
echo_success "[*] TIME CONSUMING: ${runtime}s"
