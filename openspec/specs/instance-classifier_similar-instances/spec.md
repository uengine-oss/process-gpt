# 유사 인스턴스 참고 명세

## Purpose
`instance-classifier` 서비스가 새 요청과 비슷한 과거 인스턴스와 **그 처리 결과**를 제공하여, 워크아이템 담당자가 유사 사례의 처리 방식을 참고해 일관되게 처리하도록 돕는 능력을 보장한다.

## Requirements

### Requirement: 유사 인스턴스 검색
시스템은 `GET /similar` 요청에 대해 대상 요청과 가장 유사한 과거 인스턴스 top-k를 유사도와 함께 SHALL 반환한다. 대상은 `proc_inst_id`(그 인스턴스의 요청 내용 사용, 자기 자신 제외) 또는 `text`(+ `proc_def_id`)로 지정한다.

#### Scenario: 인스턴스 기준 유사 검색
- **GIVEN** 어떤 프로세스 정의에 분류된 과거 인스턴스들이 있다
- **WHEN** 클라이언트가 `GET /similar?proc_inst_id=<id>`를 호출한다
- **THEN** 시스템은 그 인스턴스의 요청 내용과 유사한 과거 인스턴스들을 `similarity`, `topic_name`과 함께 반환하고 배정 예상 유형(`assigned_topic_id`)을 포함한다

#### Scenario: 텍스트 기준 유사 검색
- **WHEN** 클라이언트가 `GET /similar?text=<요청내용>&proc_def_id=<id>`를 호출한다
- **THEN** 시스템은 해당 정의 범위에서 그 텍스트와 유사한 과거 인스턴스들을 반환한다

### Requirement: 처리 결과 제공
시스템은 `with_outputs`가 참일 때 각 유사 인스턴스의 **완료된 워크아이템 처리 결과**를 함께 SHALL 반환한다.

#### Scenario: 처리 결과 포함
- **WHEN** 클라이언트가 `GET /similar?proc_inst_id=<id>&with_outputs=true`를 호출한다
- **THEN** 각 유사 인스턴스 항목은 완료된 워크아이템의 활동명과 처리 결과(`done_outputs`)를 포함한다

### Requirement: 담당자 참고 표면
사용자는 워크아이템 처리 화면에서 현재 인스턴스와 유사한 과거 사례 및 그 처리 결과를 유사도 순으로 확인할 수 있어야 SHALL 한다. (검증 표면)

#### Scenario: 워크아이템에서 유사 사례 확인
- **GIVEN** 사용자가 어떤 인스턴스의 워크아이템 처리 화면을 연다
- **WHEN** 사용자가 유사 사례를 조회한다
- **THEN** 화면은 유사한 과거 인스턴스를 유사도와 함께 나열하고, 각 항목을 펼치면 그 요청 내용과 함께 단계별 산출물(입력된 폼)을 읽기 좋은 형태로 하나씩 열어볼 수 있다
