# Веб-приложение академии

Рабочий интерфейс находится в `secure-dist`. Он использует Supabase Auth, серверные роли/RLS, общую базу обучения и private Storage. В публичной сборке нет ключей тестов и учебных файлов.

Запуск из `D:\Academy-Team`: `node work/preview.cjs` (порт 4173). Сборка: `node apps/web/build-secure.cjs`; Sites публикует `out`.

Схема, миграции и проверки прав: `supabase/README.md`. Эксплуатация: `../../docs/production-access.md`.

Уведомления внутри сайта: `../../docs/notifications-2026-10-24.md`; миграция 015, проверка `scripts/test-notifications.sql` с откатом и `node scripts/test-notifications.cjs`.

Старый демонстрационный прототип сохранён в `dist` вместе с оригиналами изображений и PDF, но в публикацию не входит. Демонстрационные аккаунты и результаты в рабочую базу не импортируются.
