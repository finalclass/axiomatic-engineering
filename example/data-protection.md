# Ochrona danych
[rodo]

Pacjenci mogą eksportować swoje dane w formacie strukturalnym (JSON). Eksport zawiera dane osobowe, historię wizyt i notatki terapeutyczne przypisane do pacjenta.

Pacjenci mogą usunąć swoje konto i wszystkie powiązane dane. Usunięcie jest nieodwracalne i obejmuje: dane osobowe, historię wizyt, notatki, pliki. System zachowuje jedynie zanonimizowane dane statystyczne.

Dane osobowe pacjentów nie są udostępniane podmiotom trzecim bez wyraźnej zgody.

## Bezpieczeństwo techniczne
[pentest] [test]

Hasła są hashowane algorytmem bcrypt z kosztem minimum 12. System nie przechowuje haseł w postaci jawnej.

Dane w spoczynku są szyfrowane. Komunikacja wyłącznie przez HTTPS. Certyfikat TLS minimum 2048-bit.

Dostęp do danych wrażliwych (notatki terapeutyczne, diagnoza) wymaga uwierzytelnienia dwuskładnikowego (2FA).

Sesje wygasają po 30 minutach nieaktywności. Token sesji jest regenerowany po zalogowaniu.

## Polityka prywatności
[ux-validate]

System wyświetla politykę prywatności przed rejestracją. Użytkownik musi zaakceptować politykę, aby utworzyć konto. Polityka jest napisana prostym językiem, bez żargonu prawniczego.
