# KlinikaOnline

System do zarządzania gabinetem medycznym online — rejestracja wizyt, panel pacjenta, panel terapeuty.

## Słownik

- **Pacjent** — osoba korzystająca z usług gabinetu, posiada konto w systemie
- **Terapeuta** — specjalista prowadzący wizyty, zarządza swoim kalendarzem
- **Wizyta** — zarezerwowany termin spotkania pacjenta z terapeutą
- **Grafik** — tygodniowy harmonogram dostępności terapeuty

## Labele

### [test] @implementation @validation +code
Testy jednostkowe. Pisane przed implementacją (TDD). Pokrywają logikę biznesową i walidację.

### [e2e] @validation +browser
Testy end-to-end. Pokrywają pełny flow użytkownika od wejścia na stronę do zakończenia akcji.

### [rodo] @implementation @validation +code +axioms
Wymogi RODO. Każdy aksjomat z tym labelem musi zapewniać zgodność z rozporządzeniem o ochronie danych osobowych.

### [pentest] @validation +code +api
Wymogi bezpieczeństwa weryfikowane testem penetracyjnym.

### [architecture-check] @validation +code +axioms
Weryfikacja zgodności z architekturą systemu (dekompozycja, kontrakty serwisów, warstwy).

### [ux-validate] @satisfaction(0.7) +browser
Weryfikacja użyteczności interfejsu — AI-sędzia otwiera aplikację w przeglądarce i ocenia czy UI jest zrozumiały dla użytkownika bez instrukcji.

## Aksjomaty

- [Technologia](./technology.md)
- [Ochrona danych](./data-protection.md)
- [Strona główna](./landing-client/main.md)
- [Logowanie](./login-client/login.md)
