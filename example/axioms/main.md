# KlinikaOnline

System do zarządzania gabinetem medycznym online — rejestracja wizyt, panel pacjenta, panel terapeuty.

## Słownik

- **Pacjent** — osoba korzystająca z usług gabinetu, posiada konto w systemie
- **Terapeuta** — specjalista prowadzący wizyty, zarządza swoim kalendarzem
- **Wizyta** — zarezerwowany termin spotkania pacjenta z terapeutą
- **Grafik** — tygodniowy harmonogram dostępności terapeuty

## Labele

### [test] @implementation @validation
Testy jednostkowe. Pisane przed implementacją (TDD). Pokrywają logikę biznesową i walidację.

### [e2e] @validation
Testy end-to-end. Pokrywają pełny flow użytkownika od wejścia na stronę do zakończenia akcji.

### [rodo] @implementation @validation
Wymogi RODO. Każdy aksjomat z tym labelem musi zapewniać zgodność z rozporządzeniem o ochronie danych osobowych.

### [pentest] @validation
Wymogi bezpieczeństwa weryfikowane testem penetracyjnym.

### [architecture-check] @validation
Weryfikacja zgodności z architekturą systemu (dekompozycja, kontrakty serwisów, warstwy).

### [ux-validate] @validation
Weryfikacja użyteczności interfejsu — czy UI jest zrozumiały dla użytkownika bez instrukcji.

## Aksjomaty

- [Technologia](./technology.md)
- [Ochrona danych](./data-protection.md)
- [Strona główna](./landing-client/main.md)
- [Logowanie](./login-client/login.md)
