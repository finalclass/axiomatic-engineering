# Logowanie
[test]

Strona logowania zawiera formularz z dwoma polami: email i hasło. Pod formularzem znajduje się link "Nie pamiętam hasła" prowadzący do procedury resetowania.

Po wpisaniu poprawnych danych i kliknięciu "Zaloguj się" system weryfikuje dane, tworzy sesję i przekierowuje do panelu odpowiedniego dla roli użytkownika (pacjent → panel pacjenta, terapeuta → panel terapeuty).

Przy błędnych danych system wyświetla komunikat "Nieprawidłowy email lub hasło" — bez rozróżniania, czy błędny jest email czy hasło (ochrona przed enumeracją kont).

Po 5 nieudanych próbach logowania w ciągu 15 minut konto jest tymczasowo blokowane na 30 minut. System informuje użytkownika o blokadzie i sugeruje reset hasła.

Formularz waliduje email po stronie klienta (format) i po stronie serwera (istnienie konta). Pole hasła ma minimum 8 znaków.
