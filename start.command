#!/bin/sh
# 맥에서 더블클릭으로 띄우기.
#
# 터미널을 여는 것부터가 벽인 사람이 있습니다. 이 파일을 더블클릭하면
# 터미널이 알아서 열리고 서버가 뜹니다. 끌 때는 그 창에서 Ctrl+C.
#
# 설정도 알아서 만듭니다. 터널까지 띄워서 친구에게 보낼 주소를 찍어 줍니다.
# 터널 도구가 없으면 어떻게 까는지 알려줍니다.
cd "$(dirname "$0")" || exit 1

if ! command -v node >/dev/null 2>&1; then
  echo ""
  echo "Node.js 가 없습니다."
  echo "  https://nodejs.org 에서 LTS 를 받아 깔고, 이 파일을 다시 더블클릭하세요."
  echo ""
  echo "이 창은 엔터를 치면 닫힙니다."
  read -r _
  exit 1
fi

node tools/launch.js
status=$?

echo ""
if [ $status -ne 0 ]; then
  echo "서버가 멈췄습니다. 위 내용을 보세요."
else
  echo "서버를 껐습니다."
fi
echo "이 창은 엔터를 치면 닫힙니다."
read -r _
