# HoverShot

`HoverShot`은 macOS에서 사용하는 메뉴바 유틸리티입니다.

화면 일부나 윈도우를 캡처하고, 결과를 플로팅 상태로 띄워두거나, 간단한 화면 녹화와 정리 작업까지 할 수 있습니다.

[English README](README.md)

## 현재 상태

현재 macOS에서 바로 사용 가능한 수준이며, 팀 배포용 패키징 흐름도 갖춰져 있습니다.

## 주요 기능

- 영역 캡처
- 윈도우 캡처
- 타이머 캡처
- 플로팅 샷
  - 투명도 조절
  - 표시 범위 전환
  - 클릭 스루
  - 리사이즈
  - 화면 맞춤
  - 기본 크기로 복원
- Shots Browser
  - OCR
  - 메타데이터 편집
  - 다중 선택 삭제
  - 복사 / 내보내기 / Finder 열기
- 주석 도구
  - 하이라이트
  - 가림
  - 화살표
  - 단계 번호
  - 텍스트
- 영역 / 윈도우 녹화
- Recordings Browser
  - 미리보기
  - 트림
  - GIF 내보내기
- `Settings...`에서 전역 단축키 설정

## 빠른 시작

개발 중 바로 실행:

```bash
swift run HoverShotMac
```

앱 번들 빌드:

```bash
./scripts/build-app-bundle.sh debug
open dist/HoverShot.app
```

팀 공유용 패키지 생성:

```bash
./scripts/package-team-build.sh
```

생성 결과:
- `dist/HoverShot.app`
- `dist/HoverShot-macOS.zip`
- `dist/HoverShot-macOS.sha256`
- `dist/HoverShot User Guide.md`
- `dist/HoverShot User Guide (KO).md`

## 추천 공유 방식

가장 현실적인 방식은 다음과 같습니다.
1. 소스 코드는 GitHub에 둡니다.
2. `./scripts/package-team-build.sh`로 검증된 앱 패키지를 만듭니다.
3. `dist/HoverShot-macOS.zip`을 GitHub Release에 올립니다.
4. 비개발 팀원은 소스 대신 패키지된 앱을 사용하게 합니다.

이 방식이면:
- 코드와 이슈 관리는 GitHub에서 하고
- 실제 테스트된 바이너리는 zip으로 배포하고
- 사용 가이드는 패키지 안에 함께 넣을 수 있습니다.

## 문서

- 영어 팀 배포 가이드: [docs/team-distribution.md](docs/team-distribution.md)
- 한국어 팀 배포 가이드: [docs/team-distribution.ko.md](docs/team-distribution.ko.md)
- 영어 사용자 가이드: [docs/user-guide.md](docs/user-guide.md)
- 한국어 사용자 가이드: [docs/user-guide.ko.md](docs/user-guide.ko.md)

## 참고

- 현재 빌드는 로컬 서명 기준으로 내부/팀 테스트에 맞춰져 있습니다.
- 외부 배포까지 고려하면 다음 단계는 `Developer ID 서명 + notarization`입니다.
