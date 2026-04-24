# 이메일 템플릿 (Auth / GoTrue)

회원가입 인증, 비밀번호 재설정, 초대, 이메일 변경 메일의 HTML 템플릿입니다.  
이 폴더의 파일을 수정하면 해당 이메일 내용이 바뀝니다. **컨테이너 재시작은 필요 없고**, Auth가 메일을 보낼 때마다 nginx를 통해 이 HTML을 불러옵니다.

## 파일별 용도

| 파일 | 발송 시점 |
|------|-----------|
| `confirmation.html` | 회원가입 후 이메일 인증 |
| `recovery.html` | 비밀번호 재설정 링크 요청 |
| `invite.html` | 이메일 초대 |
| `email_change.html` | 이메일 주소 변경 확인 |

## 사용 가능한 템플릿 변수 (Go Template)

- `{{ .ConfirmationURL }}` – 인증/재설정/초대 링크 (필수로 포함해야 함)
- `{{ .Email }}` – 사용자 이메일
- `{{ .SiteURL }}` – 사이트 URL (예: SITE_URL)
- `{{ .Token }}` – 6자리 OTP (링크 대신 사용 가능)
- `{{ .TokenHash }}` – 토큰 해시 (직접 링크를 만들 때 사용)
- `{{ .RedirectTo }}` – 인증 후 리다이렉트 URL
- `{{ .NewEmail }}` – 이메일 변경 시 **새 이메일** (email_change.html에서만)
- `{{ .Data }}` – user_metadata (회원가입 시 전달한 데이터)

수정 후 저장만 하면 다음 메일부터 적용됩니다.
