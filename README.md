# Spell Check

朴素，但通用的 Spell Check 拼写检查和修复工具，基于 [hunspell](https://github.com/hunspell/hunspell) 实现，用于本地和 CI 检查常见的拼写错误，欢迎 PR 贡献。

## 文件说明

`spellcheck.sh` - 拼写检查工具  
- 环境配置，首次执行会通过 Homebrew 安装 hunspell，并将 en_iOS.{dic,aff} 拷贝到 ~/Library/Spelling/ 目录  
- 分析结果输出至 spellcheck.result.txt 和 spellcheck.oclint.txt  
- spellcheck.step\*.txt 是过程文件，仅保留用于调试 

`spellcheck_mapping.sh` - 拼写错误映射表生成工具  
- 根据 spellcheck.oclint.txt 结果生成 spellcheck_error.txt 和 spellcheck_mapping.csv 文件

`spellcheck_repair.sh` - 拼写修复工具  
- 脚本提供了目录名、文件名、#import 引用、源代码 4 种类型的错误修复功能  
- 设置待修复 Module 目录，以及待过滤的 Pods 目录
- 设置 spellcheck_error.txt，待修复的拼写错误  
- 设置 spellcheck_mapping.csv，错误拼写的修正词典  
- 脚本将分析 Module 目录里的拼写错误，并且过滤掉 Pods 目录中的拼写错误（因为脚本不会做语义分析，只做符号过滤）  
- 分析结果及修复命令行输出至 spellcheck_exec.log，脚本不直接修改工程文件  
- 最后，需要手动执行 spellcheck_exec.log 脚本，完成批量修复  
- 另外，@"" 以及 @selector 等错误修正，需要人工 double check，判断是否不适合批量修复，因为一些配置 Key 或者持久化 Key 修复的话，会引起线上兼容问题  

`unmunsh.sh` - LocalDictionary 词典导出工具

`en_US.{dic,aff}` - 通用的美式英语词表  
`en_Cpp.{dic,aff}` - C++ 专用词表  
`en_iOS.{dic,aff}` - iOS 专用词表  
`spellcheck_closed_compound_words.txt` - 合成词词表
`spellcheck_*_allowlist.txt` - 白名单过滤，匹配完整的 Token，区分大小写

## 使用说明

``` bash
# 本地检查
git clone https://github.com/jiyee/spellcheck.git ~/
cd <path_of_component>
ln -s ~/spellcheck/spellcheck.sh ./

# 本地检查
./spellcheck.sh -n "<component_name>" -d ./
# 第一次使用，推荐以下方式，生成并打开结果预览文件
./spellcheck.sh -n "<component_name>" -d ./ -p # 生成结果预览文件

# Bits CI
# file_list 行格式：（示例文件在 ./examples/bits_file_list.txt）
# /Users/jiyee/spellcheck/spellcheck/examples/TTWebViewContainer.h -- 101,102,103,104
./spellcheck.sh -n "<component_name>" -f "<bits_file_list>"

# Xcode 词典导入，输出 LocalDictionary 文件
./unmunsh.sh
cat LocalDictionary >> ~/Library/Spelling/

# Unit Test
BITS_RUNNING=1 SC_DEBUG=1 ./spellcheck.sh -n local -d local -p
```

### 白名单添加方式
#### 1. Word 添加词典 en_iOS.dic  
每个 token 都是根据 CamelCase 规则拆分而成，如果一个 token 认为是可接受的 word（例如：repo 可接受），可添加到 en_iOS.dic 文件，单词小写，单词可附加前缀和后缀，具体参考 en_iOS.aff 文件


#### 2. Token 添加白名单 spellcheck_*_allowlist.txt
如果一个 token 在一个完整的符号中存在是可接受的（例如：SaaS 在 IESLiveSaaSKit 可接受，但是，按照 CamelCase 规则拆分的话，Saa 和 aaS 都不可接受），为了更准确的匹配，可添加 SaaS 到 spellcheck_App_allowlist.txt。另外，在添加的 Token 包含 ${word}，则代表检查错误结果 token，将使用正则匹配，否则使用字符串匹配（例如：${word}(OS|Phone|Pad)，可匹配 kTTShortVideoiOSPlayerType 这个符号中检查出来的 Videoi 这个错误 token 所关联的 VideoiOS ）

## Author

jiyee.sheng@gmail.com  
Nov 2, 2022  
