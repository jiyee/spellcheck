#!/bin/bash

BASE_DIR="$(dirname "$(readlink "$0")")"

$(which jq > /dev/null) || {
  brew install jq
}

if [[ -e spellcheck_mapping.csv ]]; then
  echo "已存在 spellcheck_mapping.csv 文件"
  exit 1; 
fi

if [[ ! -e spellcheck_error.txt ]]; then
  echo "[*] CREATE MISPELLING ERROR LIST FILE: spellcheck_error.txt"
  ls -1 *.oclint.txt 2>/dev/null
  if [[ $? == 0 ]]; then
    for file in *.oclint.txt; do
      while IFS= read -r line; do
        word=$(echo $line | cut -d ":" -f 1)
        token_regexp="[A-Za-z0-9\$_-]*${word}[A-Za-z0-9\$_-]*"
        token=$(echo $line | cut -d ":" -f 4- | grep -Eo "${token_regexp}" | head -1)
        echo "${word},${token}" >> spellcheck_error.tmp.txt
      done < "${file}"
    done 
    
    cat spellcheck_error.tmp.txt | sort --field-separator=, --key=1 --ignore-case | uniq > spellcheck_error.txt && rm -rf spellcheck_error.tmp.txt
  else
   echo "不存在 spellcheck_error.txt 文件"
   exit 1
 fi
  echo "[*] MISPELLING ERROR LIST FILE: spellcheck_error.txt CREATED"
fi

rm spellcheck_mapping.tmp.csv 2>/dev/null
rm spellcheck_mapping.csv 2>/dev/null
 
echo "[*] CREATE MAPPING FILE: spellcheck_mapping.csv"
while IFS= read -r line; do
  if [[ $line =~ ^(#|$) ]]; then
    continue
  fi
  
  word=$(echo $line | cut -d',' -f1)
  
  if [[ -e "${BASE_DIR}/spellcheck_mapping.csv" ]]; then
    word_fixed=$(grep -m 1 -E "^${word}," ${BASE_DIR}/spellcheck_mapping.csv)
  else
    word_fixed=""
  fi
  
  if [[ -z ${word_fixed} ]]; then
    
    # 使用独立的 GOOGLE API KEY
    GOOGLE_API_KEY=""
    GOOGLE_CX=""
    
    if [[ -n "${GOOGLE_API_KEY}" ]] && [[ -n "${GOOGLE_CX}" ]]; then
      GOOGLE_SUGGESTION=$(curl "https://www.googleapis.com/customsearch/v1?key=${GOOGLE_API_KEY}&cx=${GOOGLE_CX}&q=${word}" -s | jq '.spelling.correctedQuery' -r)
      
      if [[ -n "${GOOGLE_SUGGESTION}" ]] && [[ "${GOOGLE_SUGGESTION}" != "null" ]]; then
        echo "${word},${GOOGLE_SUGGESTION/ /}" | tee -a spellcheck_mapping.tmp.csv
      else
        echo "${word}," | tee -a spellcheck_mapping.tmp.csv
      fi
    else
      suggestion_word=$(echo "${word}" | hunspell -d "en_US,en_iOS" | perl -lne 'print $1,ucfirst($3) if /^[&#]\s*\w+\s*\d+\s*\d+\s*:\s*(\w+)(\s(\w+))?/')
      if [[ -n "${suggestion_word}" ]]; then
        echo "${word},${suggestion_word}" | tee -a spellcheck_mapping.tmp.csv
      else
        echo "${word}," | tee -a spellcheck_mapping.tmp.csv
      fi
    fi
  else
    echo "${word_fixed}" | tee -a spellcheck_mapping.tmp.csv
  fi
done < spellcheck_error.txt
echo "[*] MAPPING FILE: spellcheck_mapping.csv CREATED, PLEASE DOUBLE CHECK THE MAPPING FILE."

cat spellcheck_mapping.tmp.csv | sort --field-separator=, --key=1 --ignore-case | uniq > spellcheck_mapping.csv && rm -rf spellcheck_mapping.tmp.csv

sed -i "" -e $'1 i\\\n# 格式: 错误的 Word,完整的 Token\\\n# 说明: 错误的 Word 必填，完整的 Token 可选，存在完整的 Token，则只修正完整的 Token 关联的错误的 Word\\\n# 注释: 行首添加 # 表示跳过该错误的 Word 修复\\\n' spellcheck_error.txt
sed -i "" -e $'1 i\\\n# 格式: 错误的 Word,正确的 Word（自动修复之前，补全并人工检查正确的 Word）\\\n' spellcheck_mapping.csv
