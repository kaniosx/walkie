# Walkie - MVP

## Główny problem
Właściciele psów nie zawsze mają czas lub możliwość wyprowadzenia psa na spacer, a znalezienie dostępnej osoby „na teraz” jest trudne i zwykle wymaga pisania wiadomości, telefonów albo wcześniejszego umawiania się.

## Najmniejszy zestaw funkcjonalności
- Rejestracja i logowanie użytkowników
- Dwa typy kont:
  - właściciel psa
  - wyprowadzacz
- Dodawanie psa przez właściciela
- Możliwość zgłoszenia spaceru przyciskiem „Wyprowadź psa”
- Lista aktywnych zgłoszeń dla dostępnych wyprowadzaczy
- Akceptacja spaceru przez wyprowadzacza
- Statusy spaceru:
  - REQUESTED
  - ACCEPTED
  - IN_PROGRESS
  - COMPLETED
- Historia spacerów użytkownika
- Podstawowe zarządzanie profilem i psem
- Prosty mechanizm lokalizacji oparty o miasto lub kod pocztowy

## Co NIE wchodzi w zakres MVP
- Realtime GPS tracking
- WebSockety i live mapa
- Aplikacje mobilne
- System ocen i opinii
- Powiadomienia push
- Zaawansowany matching oparty o geolokalizację
- Automatyczne płatności i integracja Stripe
- Chat między użytkownikami
- System ubezpieczeń i weryfikacji tożsamości
- Algorytmy AI
- Zaawansowany system dostępności walkerów

## Logika biznesowa
System pozwala właścicielowi psa utworzyć zgłoszenie spaceru, które może zostać zaakceptowane przez dostępnego wyprowadzacza znajdującego się w tej samej lokalizacji.

## Kryteria sukcesu
- Użytkownik jest w stanie utworzyć zgłoszenie spaceru w mniej niż 30 sekund
- Wyprowadzacz może zaakceptować zgłoszenie i rozpocząć spacer bez kontaktu poza aplikacją
- Kluczowy flow:
  - właściciel tworzy zgłoszenie
  - wyprowadzacz akceptuje spacer
  - spacer zostaje zakończony
  działa poprawnie w teście end-to-end
- Co najmniej 80% logiki aplikacji jest pokryte testami jednostkowymi lub integracyjnymi dla najważniejszych przypadków biznesowych