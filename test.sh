#!/bin/zsh

setopt extendedglob

function exp {
  echo "$(dirname $1)/expected/$(basename $1).txt"
}

taskCount=0
function maybeWait {
  let taskCount+=1
  # spawn in batch of 20 processes
  [[ $((taskCount % 20)) = 0 ]] && wait
}

# parsing
for file in tests/parsing/{errors,infiniteLoops,recovery}/**/*.(res|resi); do
  lib/rescript.exe -recover -print ml $file &> $(exp $file) & maybeWait
done
for file in tests/parsing/{grammar,other}/**/*.(res|resi); do
  lib/rescript.exe -print ml $file &> $(exp $file) & maybeWait
done

# printing
for file in tests/{printer,conversion}/**/*.(res|resi|ml|mli); do
  lib/rescript.exe $file &> $(exp $file) & maybeWait
done
for file in tests/{printer,conversion}/**/*.re; do
  lib/refmt.exe --parse re --print binary $file | lib/rescript.exe -parse reasonBinary &> $(exp $file) & maybeWait
done
for file in tests/{printer,conversion}/**/*.rei; do
  lib/refmt.exe --parse re --print binary --interface true $file | lib/rescript.exe -parse reasonBinary -interface &> $(exp $file) & maybeWait
done

# printing with ppx
for file in tests/ppx/react/*.(res|resi); do
  lib/rescript.exe -ppx jsx $file &> $(exp $file) & maybeWait
done

wait

warningYellow='\033[0;33m'
successGreen='\033[0;32m'
reset='\033[0m'

diff=$(git ls-files --modified tests/)
if [[ $diff = "" ]]; then
  printf "${successGreen}✅ No unstaged tests difference.${reset}\n"
else
  printf "${warningYellow}⚠️ There are unstaged differences in tests/! Did you break a test?\n${diff}\n${reset}"
  exit 1
fi

# roundtrip tests
if [[ $ROUNDTRIP_TEST = 1 ]]; then
  echo "Running roundtrip tests…"
  mkdir -p temp
  roundtripTestsResult="temp/result.txt"
  touch $roundtripTestsResult

  for file in tests/idempotency/**/*.(re|rei|ml|mli); do {
    case $file in
      *.re  ) class="re"; refmtIntf=false; resIntf=""         ;;
      *.rei ) class="re"; refmtIntf=true ; resIntf=-interface ;;
      *.ml  ) class="ml"; refmtIntf=false; resIntf=""         ;;
      *.mli ) class="ml"; refmtIntf=true ; resIntf=-interface ;;
    esac
    mkdir -p temp/$(dirname $file)
    reasonBinaryFile=temp/$file.reasonBinary
    lib/refmt.exe --parse $class --print binary --interface $refmtIntf $file > $reasonBinaryFile
    sexpAst=temp/$file.sexp
    lib/rescript.exe -parse reasonBinary -print sexp $resIntf $reasonBinaryFile > $sexpAst
    rescript=temp/$file.res
    lib/rescript.exe -parse reasonBinary $resIntf $reasonBinaryFile > $rescript
    rescriptSexpAst=temp/$file.ressexp
    lib/rescript.exe -print sexp $resIntf $rescript > $rescriptSexpAst
    rescript2=temp/$file.2.res
    lib/rescript.exe $resIntf $rescript > $rescript2

    diff --unified $sexpAst $rescriptSexpAst
    [[ "$?" = 1 ]] && echo 1 > $roundtripTestsResult
    diff --unified $rescript $rescript2
    [[ "$?" = 1 ]] && echo 1 > $roundtripTestsResult
  } & maybeWait
  done

  wait

  result=$(cat $roundtripTestsResult)
  rm -r temp/

  if [[ $result = "1" ]]; then
    printf "${warningYellow}⚠️ Roundtrip tests failed.${reset}\n"
    exit 1
  else
    printf "${successGreen}✅ Roundtrip tests succeeded.${reset}\n"
  fi

fi
