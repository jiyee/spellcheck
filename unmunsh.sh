#!/bin/bash

aff='en_iOS.aff'
dic='en_iOS.dic'
rm -f LocalDictionary && touch LocalDictionary
cat "$dic" | while read -r root ; do
    root="${root%%/*}"
    echo "$root"
    wordforms "$aff" "$dic" "$root"
done \
| sort -u | uniq > LocalDictionary