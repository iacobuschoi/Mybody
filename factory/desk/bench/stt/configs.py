T = "mlx-community/whisper-large-v3-turbo"
F = "mlx-community/whisper-large-v3-mlx"
OLD = "앱 공장, 상황판, 브리핑, 클로드, 깃허브, 맥 미니, 아이폰, 안드로이드, 워크플로, 출시"
NEW = ("책상 비서에게 하는 말입니다. 핸드마우스, 조이스틱 모드, 더블클릭, 마우스 포인터, 책상 탭, 손 카메라, 다이얼, "
       "터미널, 사파리, 카카오톡, 승인, 권한, 배포, 작업 공간, 세션, 클로드, 깃허브, 앱스토어 심사, 마이바디, 상황판, 브리핑.")
CONFIGS = {
    "base": dict(model=T, prompt=OLD),                       # 지금 deskd
    "noprompt": dict(model=T),
    "newprompt": dict(model=T, prompt=NEW),
    "newprompt_gain": dict(model=T, prompt=NEW, gain=0.5),
    "base_gain": dict(model=T, prompt=OLD, gain=0.5),
    "full_new": dict(model=F, prompt=NEW),
    "full_old": dict(model=F, prompt=OLD),
}
FB = (0.0, 0.2, 0.4)
CONFIGS.update({
    "new_fb": dict(model=T, prompt=NEW, temp=FB),
    "noprompt_fb": dict(model=T, temp=FB),
    "new_loose": dict(model=T, prompt=NEW, clean=dict(no_speech_max=0.8, logprob_min=-1.3)),
    "new_fb_loose": dict(model=T, prompt=NEW, temp=FB, clean=dict(no_speech_max=0.8, logprob_min=-1.3)),
    "full_new_fb": dict(model=F, prompt=NEW, temp=FB),
})
CONFIGS.update({
    "base_pad": dict(model=T, prompt=OLD, pad=1.0),
    "new_pad": dict(model=T, prompt=NEW, pad=1.0),
    "new_pad_fb": dict(model=T, prompt=NEW, pad=1.0, temp=FB),
})

CONFIGS.update({
    "noprompt_pad": dict(model=T, pad=1.0),
    "full_new_pad": dict(model=F, prompt=NEW, pad=1.0),
})
CONFIGS.update({
    "base_fb": dict(model=T, prompt=OLD, temp=FB),
    "base_loose": dict(model=T, prompt=OLD, clean=dict(no_speech_max=0.8, logprob_min=-1.3)),
})
NEW2 = ("핸드마우스 조이스틱 모드랑 더블클릭 좀 봐 줘. 책상 탭에서 손 카메라, 마우스 포인터, 다이얼 확인하고, "
        "터미널이랑 사파리, 카카오톡, 승인, 권한, 배포, 작업 공간, 클로드 세션, 깃허브, 앱스토어 심사, 마이바디도.")
CONFIGS.update({
    "new2": dict(model=T, prompt=NEW2),
    "new_fb2": dict(model=T, prompt=NEW, temp=FB),
    "full_new2": dict(model=F, prompt=NEW),
})
CONFIGS.update({
    "full_new2_fb": dict(model=F, prompt=NEW2, temp=FB),
    "new2_fb": dict(model=T, prompt=NEW2, temp=FB),
})
