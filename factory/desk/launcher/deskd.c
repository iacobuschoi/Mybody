/* deskd — 책상 데몬을 띄우는 작은 실행 파일. 마이크 권한을 받는 "주인"입니다.
 *
 * launchd 가 파이썬을 바로 띄우면 macOS 는 마이크 권한을 Python.app 에 묻는데, Python.app 에는
 * 마이크 사용 이유(NSMicrophoneUsageDescription)가 없어서 창도 안 뜨고 0 만 들어옵니다.
 * 이 파일은 사용 이유를 담은 Info.plist 를 품고(-sectcreate __TEXT __info_plist) 파이썬을 자식으로
 * 띄웁니다 → 권한 창에 "deskd" 가 뜨고, 허용하면 자식(파이썬)도 들을 수 있습니다.
 *
 *   deskd /path/to/python -m desk run
 */
#include <errno.h>
#include <signal.h>
#include <spawn.h>
#include <stdio.h>
#include <sys/wait.h>

extern char **environ;
static pid_t child;

static void forward(int sig) {
    if (child > 0) kill(child, sig);
}

int main(int argc, char **argv) {
    if (argc < 2) {
        fprintf(stderr, "쓰는 법: deskd <프로그램> [인자…]\n");
        return 2;
    }
    signal(SIGTERM, forward);
    signal(SIGINT, forward);
    signal(SIGHUP, forward);
    int err = posix_spawn(&child, argv[1], NULL, NULL, argv + 1, environ);
    if (err) {
        fprintf(stderr, "deskd: %s 실행 실패 (%d)\n", argv[1], err);
        return 1;
    }
    int st;
    while (waitpid(child, &st, 0) < 0) {
        if (errno != EINTR) return 1;
    }
    return WIFEXITED(st) ? WEXITSTATUS(st) : 128 + WTERMSIG(st);
}
