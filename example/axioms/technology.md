# Technologia
[architecture-check]

System jest aplikacją webową. Frontend to statyczne pliki HTML/CSS/JS serwowane przez nginx. Backend to PHP 8.3 z frameworkiem Slim. Baza danych to PostgreSQL 16.

Architektura oparta na dekompozycji IDesign: managers (orkiestracja), engines (logika biznesowa), accessors (dostęp do danych), utilities (cross-cutting concerns). Każdy serwis ma wyraźny kontrakt — publiczne metody operują na business verbs, nie na CRUDach.

Frontend jest podzielony na klientów (`*-client/`), gdzie każdy klient to osobna aplikacja SPA dla jednej grupy użytkowników. Klienci współdzielą design system i komponenty UI, ale mają niezależne aksjomaty.

Deployment: kontener Docker, CI/CD przez GitHub Actions. Jeden obraz, konfiguracja przez zmienne środowiskowe.
