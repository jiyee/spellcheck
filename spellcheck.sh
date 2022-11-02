#!/usr/bin/env bash

# set -Eeuo pipefail # -o nounset/errexit/pipefail
# set -vx # -o verbose/xtrace
IFS=$'\n\t'
# export PS4='$LINENO + '

RES='\033[0m'
RED_COLOR='\033[0;31m'
GREEN_COLOR='\033[0;32m'

echo_success() {
  echo -e "${GREEN_COLOR}$1${RES}" 
}

echo_error() {
  echo -e "${RED_COLOR}$1${RES}" 
}

# CI 同样是 darwin20, CI 判断采用 WORKFLOW_JOB_URL
if [[ -z $BITS_RUNNING ]]; then
  BITS_RUNNING=0
  if [[ -n "${WORKFLOW_JOB_URL}" ]] && [[ "${WORKFLOW_JOB_URL}" != "0" ]]; then
    BITS_RUNNING=1
  fi
fi

which hunspell > /dev/null || {
  if [[ "$OSTYPE" == "linux-gnu"* ]]; then
    apt-get update
    apt-get install hunspell dictionaries-common emacsen-common hunspell-en-us libhunspell-1.7-0 libtext-iconv-perl
  elif [[ "$OSTYPE" == "darwin"* ]]; then
    brew install hunspell
  else
    help
  fi
}

which rg > /dev/null || {
  if [[ "$OSTYPE" == "linux-gnu"* ]]; then
    apt-get install ripgrep
  elif [[ "$OSTYPE" == "darwin"* ]]; then
    brew install ripgrep
  else
    help
  fi
}

which jq > /dev/null || {
  if [[ "$OSTYPE" == "linux-gnu"* ]]; then
    apt-get install jq
  elif [[ "$OSTYPE" == "darwin"* ]]; then
    brew install jq
  else
    : # do nothing, comment between if/then/else/fi
    help
  fi
}

which node > /dev/null || {
  echo_error "[*] Node.js is required."
  exit 1
}

if [[ -n $(readlink "$0") ]]; then
  BASE_DIR="$(dirname "$(readlink "$0")")"
else
  BASE_DIR="$(dirname "$0")"
fi

if [[ "$OSTYPE" == "darwin"* ]]; then
  mkdir -p ~/Library/Spelling
  cp "${BASE_DIR}"/*.aff "${BASE_DIR}"/*.dic ~/Library/Spelling/
fi

help() {
  echo "Usage: $0 -n <name> -d <directory> -f <filelist> -p"
  echo -e "\t-l spellcheck target language: [iOS|Android], default: iOS"
  echo -e "\t-n spellcheck target name"
  echo -e "\t-d spellcheck target directory"
  echo -e "\t-f spellcheck target filelist"
  echo -e "\t-p preview misspellings CSV file"
  echo -e "\t-c git clean"
  exit 1
}

unset -v SCAN_LANG SCAN_MODE SCAN_NAME SCAN_DIR SCAN_FILE_LIST SCAN_PREVIEW SCAN_CLEAN

# defaults
SCAN_LANG="iOS"
SCAN_MODE="both"
SCAN_PREVIEW=0
SCAN_CLEAN=0

while getopts "l:t:n:d:f:pc" opt; do
  case "$opt" in
  l) SCAN_LANG="$OPTARG" ;;
  t) SCAN_MODE="$OPTARG" ;;
  n) SCAN_NAME="$OPTARG" ;;
  d) SCAN_DIR="$OPTARG" ;;
  f) SCAN_FILE_LIST="$OPTARG" ;;
  p) SCAN_PREVIEW=1 ;;
  c) SCAN_CLEAN=1 ;;
  ?) help ;;
  esac
done
shift "$((OPTIND - 1))" # remove the options and optional --

if [ ${SCAN_CLEAN} -eq 1 ]; then
  git clean -xdf -e local
  echo_success "[*] git clean -xdf -e local"
  exit
fi

if [ -z "${SCAN_DIR}" ] && [ -z "${SCAN_FILE_LIST}" ]; then
  echo_error "[*] spellcheck target directory or filelist parameter is required"
  help
fi

TMP_NAME=${SCAN_NAME:-"spellcheck"}
if [[ $BITS_RUNNING -ne 1 ]]; then
  TMP_DIR=$(mktemp -d)
else
  TMP_DIR="."
fi
if [[ $SC_DEBUG -eq 1 ]]; then
  timestamp=$(date +%s)
  TMP_DIR="./tmp-${timestamp}"
  mkdir -p "${TMP_DIR}"
  
  echo_success "BITS_RUNNING: ${BITS_RUNNING}"
fi

TMP_FILE="${TMP_DIR}/${TMP_NAME}.tmp.txt"
TMP_CPP_FILE="${TMP_DIR}/${TMP_NAME}.cpp.txt"
TMP_STEP1_FILE="${TMP_DIR}/${TMP_NAME}.step1.txt"
TMP_STEP2_FILE="${TMP_DIR}/${TMP_NAME}.step2.txt"
TMP_STEP3_FILE="${TMP_DIR}/${TMP_NAME}.step3.txt"
TMP_STEP4_FILE="${TMP_DIR}/${TMP_NAME}.step4.txt"
TMP_RESULT_FILE="${TMP_DIR}/${TMP_NAME}.result.txt"
TMP_OCLINT_CSV_FILE="${TMP_DIR}/${TMP_NAME}.oclint.csv"
TMP_OCLINT_JSON_FILE="${TMP_DIR}/${TMP_NAME}_spellcheck_oclint_report.json"
TMP_NO=0

if [[ $SC_DEBUG -eq 1 ]]; then
  TMP_OCLINT_FILE="${TMP_DIR}/${TMP_NAME}.oclint.txt"
else
  TMP_OCLINT_FILE="${TMP_NAME}.oclint.txt"
fi

echo_success "[*] TMP_DIR: ${TMP_DIR}"

SCAN_LANG=$(tr '[:upper:]' '[:lower:]' <<< "${SCAN_LANG}")
if [[ "${SCAN_LANG}" == "ios" ]] \
  || [[ "${SCAN_LANG}" == "objc" ]] \
  || [[ "${SCAN_LANG}" == "swift" ]]; then
  SCAN_FILE_EXTS=(".h" ".m" ".mm" ".c" ".cc" ".hpp" ".cpp" ".swift")
  SCAN_FILE_EXCLUDES=("*.pbobjc.h" "*ApiModel.h" "*GTMNSString+HTML.h" "*.pbobjc.m" "*ApiModel.m" "*GTMNSString+HTML.m")
elif [[ "${SCAN_LANG}" == "android" ]] \
  || [[ "${SCAN_LANG}" == "java" ]] \
  || [[ "${SCAN_LANG}" == "kotlin" ]] \
  || [[ "${SCAN_LANG}" == "kt" ]]; then
  SCAN_FILE_EXTS=(".java" ".kt" ".kts")
  SCAN_FILE_EXCLUDES=()
fi

readonly SCAN_FIND_GLOB=$(for SCAN_FILE_EXT in ${SCAN_FILE_EXTS[*]}; do echo -n "-iname '*$SCAN_FILE_EXT' -or "; done)
readonly SCAN_FIND_EXCLUDE_GLOB=$(for SCAN_FILE_EXCLUDE in ${SCAN_FILE_EXCLUDES[*]}; do echo -n "! -iname '$SCAN_FILE_EXCLUDE' -and "; done)
readonly SCAN_RIPGREP_GLOB=$(for SCAN_FILE_EXT in ${SCAN_FILE_EXTS[*]}; do echo -n "--glob '*$SCAN_FILE_EXT' "; done)
readonly SCAN_RIPGREP_EXCLUDE_GLOB=$(for SCAN_FILE_EXCLUDE in ${SCAN_FILE_EXCLUDES[*]}; do echo -n "--glob '!$SCAN_FILE_EXCLUDE' "; done)
readonly SCAN_GREP_GLOB=$(for SCAN_FILE_EXT in ${SCAN_FILE_EXTS[*]}; do echo -n "--include='*$SCAN_FILE_EXT' "; done)
readonly SCAN_GREP_EXCLUDE_GLOB=$(for SCAN_FILE_EXCLUDE in ${SCAN_FILE_EXCLUDES[*]}; do echo -n "--exclude='$SCAN_FILE_EXCLUDE' "; done)

function cleanup() {
  echo "No.$((TMP_NO+=1)) - Cleanup"
  
  rm -f "${TMP_FILE}"
  rm -f "${TMP_CPP_FILE}"
  rm -f "${TMP_STEP1_FILE}"
  rm -f "${TMP_STEP2_FILE}"
  rm -f "${TMP_STEP3_FILE}"
  rm -f "${TMP_STEP4_FILE}"
  rm -f "${TMP_RESULT_FILE}"
  rm -f "${TMP_OCLINT_CSV_FILE}"
  rm -f "${TMP_OCLINT_JSON_FILE}"
}

if [[ $BITS_RUNNING -ne 1 ]] && [[ $SC_DEBUG -ne 1 ]]; then
  trap cleanup EXIT
fi

function dump_code_in_directory() {
  echo "No.$((TMP_NO+=1)) - Dump code from the directory ${SCAN_DIR}" 
  
  if [[ "${SCAN_MODE}" == "both" ]] || [[ "${SCAN_MODE}" == "path" ]]; then
    # 用于判断是否包含 C++ 文件，增加额外的字典
    find -L "${SCAN_DIR}" -type f -iname '*.hpp' -or -iname '*.mm' -or -iname '*.c' -or -iname '*.cc' -or -iname '*.cpp' > "${TMP_CPP_FILE}"
    {
      echo "### [BEGIN] FILE NAMES ###"
      sh -c "find -L \"${SCAN_DIR}\" -type f \( ${SCAN_FIND_GLOB% -or } \) -and ${SCAN_FIND_EXCLUDE_GLOB% -and }"
      echo "### [END] FILE NAMES ###"
    } > "${TMP_FILE}"
  fi
  
  if [[ "${SCAN_MODE}" == "both" ]] || [[ "${SCAN_MODE}" == "code" ]]; then
    find -L "${SCAN_DIR}" -type f -iname '*.h' -or -iname '*.hpp' | xargs -I{} sh -c "cat '{}'; echo ''" >> "${TMP_CPP_FILE}"
    
    {
      sh -c "find -L \"${SCAN_DIR}\" -type f \( ${SCAN_FIND_GLOB% -or } \) -and ${SCAN_FIND_EXCLUDE_GLOB% -and }" | xargs -I{} sh -c "cat '{}'; echo ''"
    } >> "${TMP_FILE}"
  fi
}

function dump_code_from_filelist() {
  echo "No.$((TMP_NO+=1)) - Dump code from file list ${SCAN_FILE_LIST}"
  
  cp "${SCAN_FILE_LIST}" "./${TMP_NAME}.bits_file_list.txt"
  
  awk -F '--' '{print $1}' "${SCAN_FILE_LIST}" > "${TMP_CPP_FILE}"
  while IFS= read -r line || [ -n "${line}" ]; do
    if echo "${line}" | awk -F '--' '{print $1}' | grep -qE '\.h(pp)?\s*$'; then
      echo "${line}" | awk -F '--' '{print $1}' | xargs -I{} sh -c "cat {}" >> "${TMP_CPP_FILE}"
    fi
 
    # FIX: CI 变更行数 > 430 时 sed 命令溢出，判断是否新增文件，1..last 方式
    line_seq=$(echo "${line}" | awk -F '--' '{gsub(/[ \t]/, "", $2); print $2}')
    line_last=$(echo "${line_seq}" | awk -F ',' '{print $NF}')
    line_one_to_last=$(seq 1 "${line_last}" | tr '\n' ',' | perl -pe 's/,$//')
    if [[ "${line_seq}" == "${line_one_to_last}" ]]; then
      echo "${line}" | awk -F ' -- ' -v line_last="${line_last}" '{print "head -n " line_last " " "\"" $1 "\""}' | sh >> "${TMP_FILE}"
    else
      echo "${line}" | awk -F ' -- ' '{gsub(/$/, "p;", $2); gsub(/,/, "p;", $2); gsub(/[ \t]/, "", $2); print "sed -n \"" $2 "\" " "\""$1"\""}' | sh >> "${TMP_FILE}"
    fi
  done < "${SCAN_FILE_LIST}"
}

function extract_tokens() {
  echo "No.$((TMP_NO+=1)) - Extract tokens"
  
  # line -> token，过滤掉宏定义，超长 "" 内容，url，color hex 
  
  < "${TMP_FILE}" \
    perl -pe 's/"[0-9a-zA-Z\,\:\;\/\\\.\_\-\=\+\~\?\|]{50,}"//g' \
  | perl -pe 's/\/\/(\\(.|\r?\n)|[^\\\n])*//g' \
  | perl -pe 's/^[ \s\t]*(\/\/|\/\*|#|\*)(\\(.|\r?\n)|[^\\\n])*//g' \
  | perl -pe 's/\/\*.*\*/\//g' \
  | perl -pe 's/^[ \s\t]*#\s*(import|include|pragma|if|elif|else|endif|define|undef|line|warning|error).*$//g' \
  | perl -pe 's/^[ \s\t]*\*.*$//g' \
  | perl -pe 's/"[0-9a-zA-Z\,\:\;\/\\\.\_\-\=\+\~\?\|]{50,}"//g' \
  | perl -pe 's/^\.\/\/.*\.(h|m|mm)$//g' \
  | perl -pe 's/"(http|https|sslocal|snssdk)[^"]+"//g' \
  | perl -pe 's/"(0x|#)[a-zA-Z0-9]{2,}"//g' \
  | perl -pe 's/"[a-fA-F0-9]{6}"//g' \
  | perl -pe 's/"[a-fA-F0-9]{8}"//g' \
  | perl -pe 's/\\n(?=.*")/ /g' \
  | perl -pe 's/[^0-9a-zA-Z]|[^[:alnum:]]/ /g' \
  | perl -pe 's/[ \s\t]/
  /g' \
  | perl -pe 's/[[:blank:]]+//g' \
  | sort \
  | uniq \
  > "${TMP_STEP1_FILE}"
}

function extract_words() {
  echo "No.$((TMP_NO+=1)) - Extract words"
  
  # token -> word，过滤掉 ObjC 前缀，数字

  < "${TMP_STEP1_FILE}" \
    perl -pe 's/((?<![A-Z])[A-Z][^A-Z.])/
  \1/g' \
  | perl -pe 's/([A-Z]{2,})([A-Z][a-rt-z])/
  \1 \2/g' \
  | perl -pe 's/(?<=[a-z])(([A-Z]{2,}s?))/\n\1/g' \
  | perl -pe 's/[ \s\t]/
  /g' \
  | perl -pe 's/[[:blank:]]+//g' \
  | perl -pe 's/^0x[a-zA-Z0-9]+$//g' \
  | perl -pe 's/(^\d+|\d+$)//g' \
  | grep -E '^.{4,24}$' \
  | grep -vE '^[A-Z]+$' \
  | grep -vE '^[A-Z]{2,}s$' \
  | grep -vE '^[A-Z]{2,}Is$' \
  | perl -pe 's/^([A-Z]+)([A-Z][a-z]*)$/\2/g' \
  | grep -vE '^(TT|Tt|tt|TV|BD|Bd|bd|XG|Xg|xg)[a-zA-Z]{1,3}|(TSV|TIM|TMA)[a-zA-Z]{1,2}$' \
  | grep -E '^.{4,}$' \
  | sort \
  | uniq \
  > "${TMP_STEP2_FILE}"
}

function download_bits_allowlist() {
  echo "No.$((TMP_NO+=1)) - Downloading Bits_Allowlist.dic"
  
  # 下载 Bits_Allowlist.dic，Bits 手动误报的白名单
  
  rm Bits_Allowlist.dic 2>/dev/null
  curl "https://noop.com/spellcheck_bits_allowlist" --retry 1 --silent --output "${BASE_DIR}/Bits_Allowlist.dic" # 手动替换白名单链接
  
  if [[ "$OSTYPE" == "darwin"* ]]; then
    mkdir -p ~/Library/Spelling
    cp "${BASE_DIR}/Bits_Allowlist.dic" ~/Library/Spelling/
  fi
  
  # 添加 committer 到白名单，A/B Test 代码里要求填写作者名称
  if [[ $BITS_RUNNING -eq 1 ]] && [[ -n "${WORKFLOW_PIPELINE_USER}" ]]; then
    echo "" >> Bits_Allowlist.dic
    echo "${WORKFLOW_PIPELINE_USER}" | perl -pe 's/\./\n/' >> Bits_Allowlist.dic
  fi
}

function run_hunspell_using_en_US() {
  echo "No.$((TMP_NO+=1)) - Run hunspell using dict en_US"
  
  # 第一次使用 en_US 词典抽取出 & 和 # 结果

  < "${TMP_STEP2_FILE}" hunspell -d en_US | grep -E '^[&#]' | cut -d' ' -f2 \
  | sort --ignore-case \
  | uniq \
  > "${TMP_STEP3_FILE}"
}

function using_dict_within_cpp_files() {
  # 判断是否包含 C++ 源代码，增加 en_Cpp 词典
  
  if grep -qE "(^\s*template\s*<|std::|^\s*namespace\s+|\.hpp\s*$|\.mm\s*$|\.c\s*$|\.cc\s*$)" "${TMP_CPP_FILE}"; then
    echo "en_iOS,Bits_Allowlist,en_Cpp,en_US"
  else
    echo "en_iOS,Bits_Allowlist,en_US"
  fi
}

function run_hunspell_using_en_iOS() {
  dicts=$(using_dict_within_cpp_files)
  
  echo "No.$((TMP_NO+=1)) - Run hunspell using dict ${dicts}"
  
  # en_iOS.dic 词典全都小写，其实 hunspell 不区分大小写

  < "${TMP_STEP3_FILE}" tr '[:upper:]' '[:lower:]' | hunspell -d "${dicts}" | grep -E '^[&#]' | cut -d' ' -f2 | sort --ignore-case | uniq > "${TMP_STEP4_FILE}"
}

function run_hunspell_by_removing_prefix_or_suffix() {
  dicts=$(using_dict_within_cpp_files)
  
  echo "No.$((TMP_NO+=1)) - Run hunspell by removing common prefix and suffix"
  
  # 如果 word 包含常见的前后缀，尝试移除前后缀之后重新检查，判定一些自定义词汇
  
  local word_list=()
  while read -r word; do
    if [[ $word =~ [a-z]{6,} ]]; then
      if [[ "${word}" =~ ^(pre|re|en|un|de|dis|auto) ]]; then
        word_fixed=$(echo "${word}" | perl -pe "s/^(pre|re|en|un|de|dis|auto)//")
        ret=$(echo "${word_fixed}" | hunspell -d "${dicts}" -G)
        if [[ $ret != "" ]]; then
          word_list+=("${word}")
        fi
      fi
      
      if [[ "${word}" =~ (d|ed|ness|able|ment|er|ers|est|ing|ly|ive|ion|ify)$ ]]; then
        word_fixed=$(echo "${word}" | perl -pe "s/(d|ed|ness|able|ment|er|ers|est|ing|ly|ive|ion|ify)$//")
        ret=$(echo "${word_fixed}" | hunspell -d "${dicts}" -G)
        if [[ $ret != "" ]]; then
          word_list+=("${word}")
        fi
      fi
    fi
  done < "${TMP_STEP4_FILE}"
  
  for word in "${word_list[@]}"; do
    sed -i "" -e "/^\(${word}\)\$/d" "${TMP_STEP4_FILE}"
  done
}

function export_hunspell_result() {
  echo "No.$((TMP_NO+=1)) - Export hunspell result to ${TMP_NAME}.result.txt"
  
  # 抽取出包含大小写的 word 结果

  # NOTICE: grep 存在 bug, 例如 step4 和 step3 都存在 cache 和 cached, 只返回 cache, rg 不存在 bug
  if which rg > /dev/null; then
    rg -iFxf "${TMP_STEP4_FILE}" "${TMP_STEP3_FILE}" | sort --ignore-case > "${TMP_RESULT_FILE}"
  else
    grep -iFxf "${TMP_STEP4_FILE}" "${TMP_STEP3_FILE}" | sort --ignore-case > "${TMP_RESULT_FILE}"
  fi
}

function check_closed_compound_word_misspelling() {
  echo "No.$((TMP_NO+=1)) - Check misspelled closed compound words"
  
  # 检查 word 是否在合成词列表，例如 RelationShip
  raw_closed_compound_words=$(comm -23 \
    <(rg -I --ignore-case --fixed-strings --only-matching -f "${BASE_DIR}/spellcheck_closed_compound_words.txt" "${TMP_STEP1_FILE}" | grep -Ev '^[A-Z]([a-z]+|[A-Z]+)$' | sort | uniq) \
    <(rg -I --fixed-strings --only-matching -f "${BASE_DIR}/spellcheck_closed_compound_words.txt" "${TMP_STEP1_FILE}" | grep -Ev '^[A-Z]([a-z]+|[A-Z]+)$' | sort | uniq) \
    | sort | uniq)
    
  # 过滤类似 PinTo -> inTo 误报情况
  for word in ${raw_closed_compound_words}; do
    if [[ "${word}" =~ ^[a-z] ]]; then
      if grep -qE "(^|.)${word}" "${TMP_STEP1_FILE}"; then
        continue
      fi
    fi
    
    echo "${word}" >> "${TMP_RESULT_FILE}"
  done
}

function export_oclint_reporter() {
  echo "No.$((TMP_NO+=1)) - Export misspellings to ${TMP_NAME}.oclint.txt"
  
  if [[ -e "${TMP_OCLINT_FILE}" ]]; then
      rm -rf "${TMP_OCLINT_FILE}"
  fi
  
  touch "${TMP_OCLINT_FILE}"
  
  if [[ -n "${SCAN_DIR}" ]] && [[ -d "${SCAN_DIR}" ]]; then
    upper_case_pattern=$(grep -E '^[A-Z]' "${TMP_RESULT_FILE}" | sort | tr '\r\n' '|' | perl -pe 's/\|$//')
    lower_case_pattern=$(grep -E '^[a-z]' "${TMP_RESULT_FILE}" | sort | tr '\r\n' '|' | perl -pe 's/\|$//')
    pattern="(${upper_case_pattern:-JIYEE}|((?=^)|(?<=[^a-z]))(${lower_case_pattern:-jiyee}))(?=[^a-z]|$)"
    
    # 遍历源代码拼写错误结果
    if [[ "${SCAN_MODE}" == "both" ]] || [[ "${SCAN_MODE}" == "code" ]]; then
      # 性能优化，采用一次遍历方式，采用 JSON 解析方式，jq 命令不熟悉，写得丑
      sh -c "rg -e \"${pattern}\" --pcre2 --json ${SCAN_RIPGREP_GLOB} ${SCAN_RIPGREP_EXCLUDE_GLOB} \"${SCAN_DIR}\"" \
        | jq '. | select(.type == "match")' \
        | jq 'if (.data.submatches | length) == 5 then
            (.data.submatches[0].match.text, ":", .data.path.text, ":", .data.line_number, ":", .data.lines.text), "\r\n",
            (.data.submatches[1].match.text, ":", .data.path.text, ":", .data.line_number, ":", .data.lines.text), "\r\n",
            (.data.submatches[2].match.text, ":", .data.path.text, ":", .data.line_number, ":", .data.lines.text), "\r\n",
            (.data.submatches[3].match.text, ":", .data.path.text, ":", .data.line_number, ":", .data.lines.text), "\r\n",
            (.data.submatches[4].match.text, ":", .data.path.text, ":", .data.line_number, ":", .data.lines.text), "\r\n" 
          elif (.data.submatches | length) == 4 then
            (.data.submatches[0].match.text, ":", .data.path.text, ":", .data.line_number, ":", .data.lines.text), "\r\n",
            (.data.submatches[1].match.text, ":", .data.path.text, ":", .data.line_number, ":", .data.lines.text), "\r\n",
            (.data.submatches[2].match.text, ":", .data.path.text, ":", .data.line_number, ":", .data.lines.text), "\r\n",
            (.data.submatches[3].match.text, ":", .data.path.text, ":", .data.line_number, ":", .data.lines.text), "\r\n"
          elif (.data.submatches | length) == 3 then
            (.data.submatches[0].match.text, ":", .data.path.text, ":", .data.line_number, ":", .data.lines.text), "\r\n",
            (.data.submatches[1].match.text, ":", .data.path.text, ":", .data.line_number, ":", .data.lines.text), "\r\n",
            (.data.submatches[2].match.text, ":", .data.path.text, ":", .data.line_number, ":", .data.lines.text), "\r\n"
          elif (.data.submatches | length) == 2 then
            (.data.submatches[0].match.text, ":", .data.path.text, ":", .data.line_number, ":", .data.lines.text), "\r\n",
            (.data.submatches[1].match.text, ":", .data.path.text, ":", .data.line_number, ":", .data.lines.text), "\r\n"
          elif (.data.submatches | length) == 1 then
            (.data.submatches[0].match.text, ":", .data.path.text, ":", .data.line_number, ":", .data.lines.text), "\r\n"
          else "" end' -j \
        | sort --field-separator=: --key=1n \
        | uniq \
        | grep -Ev '#(import|pragma)' \
        | grep -Ev '(\/\/|\*)\s+(Created\s+by|Copy[Rr]ight)' \
        | grep -Ev '^[\s\t ]*\r?\n$' > "${TMP_OCLINT_FILE}"
    fi

    # 遍历路径拼写错误结果
    if [[ "${SCAN_MODE}" == "both" ]] || [[ "${SCAN_MODE}" == "path" ]]; then
      sed -n "/### \[BEGIN\] FILE NAMES ###/,/### \[END\] FILE NAMES ###/p" "${TMP_FILE}" \
        | rg -e "${pattern}" --pcre2 --json \
        | jq '. | select(.type == "match")' \
        | jq 'if (.data.submatches | length) == 2 then 
            (.data.submatches[0].match.text, ":", (.data.lines.text | sub("\n$"; "")), ":", "0", ":", .data.lines.text), "\r\n",
            (.data.submatches[1].match.text, ":", (.data.lines.text | sub("\n$"; "")), ":", "0", ":", .data.lines.text), "\r\n"
          elif (.data.submatches | length) == 1 then
            (.data.submatches[0].match.text, ":", (.data.lines.text | sub("\n$"; "")), ":", "0", ":", .data.lines.text), "\r\n"
          else "" end' -j \
        | sort --field-separator=: --key=1n \
        | uniq \
        | grep -Ev "/^[\s\t ]*\r?\n$/d" >> "${TMP_OCLINT_FILE}"
    fi
    
    # 过滤掉 ackground 这种单个错误，连带检查出来的正确拼写代码行
    lower_case_words=$(rg '^[a-z]+:' "${TMP_OCLINT_FILE}" | cut -d':' -f1,4 | rg --pcre2 '(^[a-z]+):.*[A-Z]\1' | cut -d":" -f1 | sort | uniq)
    for lower_case_word in $lower_case_words; do
      lower_case_words_in_line=$(rg --only-matching "^${lower_case_word}:.*([A-Z]${lower_case_word})" -r "\$1" "${TMP_OCLINT_FILE}" | sort | uniq)
      for camel_case_word_in_line in $lower_case_words_in_line; do
        ret=$(echo "${camel_case_word_in_line}" | hunspell -d "en_US,en_iOS" -G)
        if [[ ${ret} != "" ]]; then
          perl -i -pe "s/^${lower_case_word}:.*${camel_case_word_in_line}.*$//g" "${TMP_OCLINT_FILE}"
        fi
      done
    done

  elif [[ -n "${SCAN_FILE_LIST}" ]] && [[ -f "${SCAN_FILE_LIST}" ]]; then

    # read returns a falsy value if it meets end-of-file before a newline, but even if it does, it still assigns the value it read.
    while IFS= read -r word || [ -n "$word" ]; do
      if [[ ${word:0:1} =~ [a-z] ]]; then
        regexp="([^a-z]|^)$word([^a-z]|$)"
      else
        regexp="$word([^a-z]|$)"
      fi
      
      awk -F " -- " '{print $1}' "${SCAN_FILE_LIST}" | while read -r file || [ -n "${file}" ]; do
        sh -c "grep -EIHnr ${SCAN_GREP_GLOB} ${SCAN_GREP_EXCLUDE_GLOB} \"${regexp}\" \"${file}\"" \
        | grep -Ev '#(import|pragma)' \
        | grep -Ev '\/\/\s*Created\s*by' \
        | awk -F ':' -v word="${word}" '{print word ":" $0}' >> "${TMP_OCLINT_FILE}"
      done
    done < "${TMP_RESULT_FILE}"

  fi
  
  # 过滤 allowlist
  echo "No.$((TMP_NO+=1)) - Exclude words in allowlist"
  
  # 增加 ${word} 通配符的正则匹配
  cat "${BASE_DIR}/"spellcheck_*_allowlist.txt | while IFS= read -r allowlist || [ -n "$allowlist" ]; do
    # kTTShortVideoiOSPlayerType -> Videoi -> Videoi(OS|Phone|Pad)
      
    if [[ -z ${allowlist} ]] || [[ $allowlist =~ ^# || $allowlist =~ ^[\s\t]*$ ]]; then
      continue
    fi
    
    allowlist_regexp=$(echo "${allowlist}" | perl -pe "s/\\$\{\word\}//") # 移除 ${word} 占位符，只包含正则匹配部分（断言）
    perl -ne "print if /${allowlist_regexp}/" "${TMP_OCLINT_FILE}" | while IFS=":" read -r word _ _ raw_line; do
      token_regexp="[A-Za-z0-9\$_-]*${word}[A-Za-z0-9\$_-]*"
      token=$(echo "${raw_line}" | grep -Eo "${token_regexp}" | head -1)
      
      if [[ -z ${token} ]] || [[ $token =~ ^# || $token =~ ^[\s\t]*$ ]]; then
        continue
      fi
      
      word_regexp=$(echo "${allowlist}" | perl -pe "s/\\$\{\word\}/${word}/")
      if echo "${word_regexp}" | grep -qF "${word}" && echo "${token}" | rg --pcre2 --quiet "${word_regexp}"; then
        perl -i -pe "s/^${word}:.*:\d+:.*${word_regexp}.*$//g" "${TMP_OCLINT_FILE}"
      fi
    done
  done
  
  # 移除空行
  perl -i -ne 'print unless /^\s*\r?\n?$/' "${TMP_OCLINT_FILE}"
  
  if [[ $SCAN_PREVIEW -eq 1 ]]; then
    echo "No.$((TMP_NO+=1)) - Generate CSV reporter file in ${TMP_NAME}.oclint.csv"
    
    which csvtotable > /dev/null || {
      pip install csvtotable
    }
    
    < "${TMP_OCLINT_FILE}" awk -F ':' '{printf "%s,%s:%s,€", $1, $2, $3} {for(i=4;i<=NF;++i) {printf "%s", $i}  printf "€\n"}' > "${TMP_OCLINT_CSV_FILE}"
    
    if [ $(wc -l < "${TMP_OCLINT_FILE}") -lt 500 ]; then
      sed -i "" -e $'1 i\\\nWord,Token,File Path,Source Line of Code\n' "${TMP_OCLINT_CSV_FILE}"
      line_number=2
      while IFS=":" read -r word _ _ raw_line; do
        token_regexp="[A-Za-z0-9\$_-]*${word}[A-Za-z0-9\$_-]*"
        token=$(echo "${raw_line}" | grep -Eo "${token_regexp}" | head -1)
        sed -i "" -e "${line_number} s/^${word},/${word},${token},/" "${TMP_OCLINT_CSV_FILE}"
        line_number=$((line_number + 1))
      done < "${TMP_OCLINT_FILE}"
    else
      sed -i "" -e $'1 i\\\nWord,File Path,Source Line of Code\n' "${TMP_OCLINT_CSV_FILE}"
    fi
    
    which csvtotable > /dev/null && {
      if [[ -s "${TMP_OCLINT_CSV_FILE}" ]]; then
        echo "No.$((TMP_NO+=1)) - Serving CSV file ${TMP_NAME}.oclint.csv using csvtotable"
        csvtotable "${TMP_OCLINT_CSV_FILE}" --serve --virtual-scroll 0 --delimiter ',' --quotechar '€' --caption "spellcheck.sh - ${TMP_NAME}.oclint.csv"
      else
        echo -e "\033[0;32m[*] GOOD JOB, NO MISSPELLING FOUND.\033[0m"
      fi
    }
  fi
}

if [[ -n "${SCAN_DIR}" ]] && [[ -d "${SCAN_DIR}" ]]; then
  dump_code_in_directory
elif [[ -n "${SCAN_FILE_LIST}" ]] && [[ -f "${SCAN_FILE_LIST}" ]]; then
  dump_code_from_filelist
else
  echo "spellcheck target directory or filelist parameter is required"
  help
fi

extract_tokens
extract_words
download_bits_allowlist
run_hunspell_using_en_US
run_hunspell_using_en_iOS
run_hunspell_by_removing_prefix_or_suffix
export_hunspell_result
check_closed_compound_word_misspelling
export_oclint_reporter
