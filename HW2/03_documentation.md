# Домашнее задание №2. Ограничения целостности и индексы

**Студент:** Раднаев Зоригто Батоевич, группа ДЭ 15-25
**Домен:** Вариант 1 — Онлайн-курсы (EdTech), схема из ДЗ №1

**Файлы сдачи:**
1. `01_schema_additions.sql` — две новые таблицы, ограничения, индексы, тестовые данные (запускать после `schema.sql`);
2. `02_constraint_violations_demo.sql` — 5 демонстраций нарушений (`DO $$ ... EXCEPTION ... END $$`);
3. `03_documentation.md` — этот файл.

Скрипты проверены на PostgreSQL 16: `schema.sql` → `01_schema_additions.sql` → `02_constraint_violations_demo.sql`. Файл 01 можно запускать повторно.

---

## Часть 1. Дополнение схемы

### 1.1. Новые таблицы

**`categories`** — справочник категорий курсов.

| Столбец | Тип | Ограничения |
|---|---|---|
| category_id | SERIAL | PRIMARY KEY |
| name | VARCHAR(100) | NOT NULL, UNIQUE, CHECK (непустое после `trim`) |
| slug | VARCHAR(100) | NOT NULL, UNIQUE, CHECK (формат `^[a-z0-9]+(-[a-z0-9]+)*$`) |
| description | TEXT | — |
| created_at | TIMESTAMPTZ | NOT NULL, DEFAULT now |

**`course_categories`** — связующая таблица M:N «курс ↔ категория».

| Столбец | Тип | Ограничения |
|---|---|---|
| course_id | INTEGER | NOT NULL, FK → `courses` (ON DELETE **CASCADE**) |
| category_id | INTEGER | NOT NULL, FK → `categories` (ON DELETE **RESTRICT**) |
| is_primary | BOOLEAN | NOT NULL, DEFAULT FALSE |
| assigned_at | TIMESTAMPTZ | NOT NULL, DEFAULT now |
| | | PRIMARY KEY (course_id, category_id) |

Дополнительно: частичный уникальный индекс `uq_cc_one_primary_per_course ON course_categories (course_id) WHERE is_primary` гарантирует не более одной основной категории у курса.

### 1.2. Реализация связи M:N

**Способ:** отдельная связующая (ассоциативная) таблица `course_categories` с составным первичным ключом `(course_id, category_id)` и двумя внешними ключами.

**Почему так:**
- В реляционной модели связь M:N нельзя выразить одним внешним ключом. Массив `category_ids INTEGER[]` в `courses` не поддерживает FK, поэтому целостность пришлось бы проверять вручную.
- Составной PK запрещает дубли пары «курс — категория» и одновременно даёт индекс для запроса «категории курса».
- В связующей таблице можно хранить атрибуты самой связи (`is_primary`, `assigned_at`).
- Тот же приём уже применён в ДЗ №1: `enrollments` связывает `users` и `courses`, а `lesson_progress` связывает `enrollments` и `lessons`.

**Политики удаления:**
- Удаление курса (`ON DELETE CASCADE`) удаляет только его «ярлыки» категорий. Сам ярлык без курса бессмыслен.
- Удаление категории (`ON DELETE RESTRICT`) запрещено, пока в ней есть курсы. Так администратор не потеряет классификацию курсов случайно и сначала перенесёт курсы в другую категорию.

### 1.3. Что будет при `DROP ... CASCADE` (доп. балл)

`ON DELETE CASCADE` и `DROP TABLE ... CASCADE` — разные вещи:

| | `ON DELETE CASCADE` | `DROP TABLE ... CASCADE` |
|---|---|---|
| Уровень | строки (при `DELETE`) | объекты схемы (DDL) |
| Что удаляется | зависимые **строки** дочерней таблицы | зависимые **объекты**: FK-ограничения, представления и т.п. |
| Данные дочерних таблиц | удаляются вместе со строкой родителя | **остаются**, таблицы не удаляются |

Для нашей схемы:
- `DROP TABLE categories CASCADE` удалит саму `categories` и FK `fk_cc_category` из `course_categories`. Таблица `course_categories` и её строки сохранятся, но `category_id` в них перестанет быть внешним ключом, и в нём останутся «висячие» значения.
- `DROP TABLE courses CASCADE` удалит `courses` и FK-ограничения, ссылающиеся на неё, из `lessons`, `enrollments`, `reviews` и `course_categories`. Сами эти таблицы и данные останутся, но без контроля ссылочной целостности.
- Поэтому в начале `schema.sql` таблицы удаляются в порядке от дочерних к родительским, а `CASCADE` нужен только для повторного запуска. В рабочей БД `DROP ... CASCADE` без предварительной проверки зависимостей выполнять опасно.

### 1.4. Дополнительные ограничения на существующих таблицах

| Таблица | Ограничение | Смысл |
|---|---|---|
| users | `chk_users_email_format` | e-mail должен иметь вид `имя@домен.зона` |
| lesson_progress | `chk_progress_completed_consistency`: `is_completed = (completed_at IS NOT NULL)` | урок считается пройденным только с датой прохождения, и наоборот |

### 1.5. Индексы под частые запросы из ДЗ №1

| Запрос из ДЗ №1 | Что использует | Индекс |
|---|---|---|
| 1. Каталог опубликованных курсов (со средним рейтингом) | фильтр `is_published`, сортировка по дате; `AVG(rating)` по курсу | `idx_courses_published (created_at DESC) WHERE is_published`; `idx_reviews_course_rating (course_id, rating)` |
| 2. Топ-10 по числу отзывов и оценке | `COUNT(*)`, `AVG(rating)` `GROUP BY course_id` | `idx_reviews_course_rating` — index-only scan |
| 3. Уроки курса по `order_number` | `WHERE course_id = ? ORDER BY order_number` | индекс под `uq_course_order (course_id, order_number)` — данные уже отсортированы |
| 4. История обучения студента и % прохождения | `enrollments` по `student_id`; `lesson_progress` по `enrollment_id` | индексы под `uq_student_course` и `uq_enrollment_lesson`; `idx_progress_enrollment_completed` (частичный, только пройденные) |
| 5. Доход преподавателя за месяц | `courses` по `teacher_id`, `enrollments` по `course_id` + диапазон `enrolled_at`, суммирование `price_paid` | `idx_courses_teacher_id`; `idx_enrollments_course_enrolled (course_id, enrolled_at) INCLUDE (price_paid, status)` |

**Удалены как избыточные** (их полностью покрывают индексы UNIQUE-ограничений с тем же ведущим столбцом, а лишние индексы замедляют `INSERT`/`UPDATE`): `idx_lessons_course_id`, `idx_enrollments_student_id`, `idx_reviews_student_id`, `idx_progress_enrollment_id`. Индексы `idx_reviews_course_id` и `idx_enrollments_course_id` заменены более полными составными.

**Индексы FK для новых таблиц:** PK `(course_id, category_id)` покрывает поиск по `course_id`; для `category_id` добавлен `idx_cc_category_course`. Он нужен и для быстрой проверки `ON DELETE RESTRICT` при удалении категории.

---

## Часть 2. Демонстрация нарушений

Скрипт `02_constraint_violations_demo.sql` содержит ровно 5 блоков `DO $$ ... EXCEPTION ... END $$`. В каждом блоке:
- ошибка перехватывается по конкретному условию (`check_violation`, `foreign_key_violation`, `unique_violation`, `not_null_violation`), а всё неожиданное ловится через `WHEN others`;
- через `GET STACKED DIAGNOSTICS` выводится имя нарушенного ограничения или колонки;
- сообщение объясняет бизнес-смысл и содержит `SQLERRM`;
- данные не меняются, так как PostgreSQL откатывает действия блока при ошибке.

---

## Часть 3. Документирование нарушений

| № | Ограничение | Выполняемый запрос (SQL) | Сообщение СУБД | Понятное сообщение для пользователя | Как исправить |
|---|---|---|---|---|---|
| 1 | CHECK (`reviews_rating_check`) | `INSERT INTO reviews (student_id, course_id, rating, comment) VALUES (4, 1, 7, '...');` | `new row for relation "reviews" violates check constraint "reviews_rating_check"` | «Оценка курса должна быть целым числом от 1 до 5» | Указать оценку в диапазоне 1–5 |
| 2 | FOREIGN KEY (`fk_enrollments_course`) | `INSERT INTO enrollments (student_id, course_id, price_paid) VALUES (4, 999, 1000.00);` | `insert or update on table "enrollments" violates foreign key constraint "fk_enrollments_course"` | «Нельзя записаться на курс, которого не существует» | Указать существующий `course_id` (проверить каталог курсов) |
| 3 | UNIQUE (`uq_student_course`) | `INSERT INTO enrollments (student_id, course_id, price_paid) VALUES (3, 1, 1990.00);` | `duplicate key value violates unique constraint "uq_student_course"` | «Студент уже записан на этот курс, повторно купить его нельзя» | Не создавать дубль записи; для продолжения обучения использовать существующую запись `enrollments` |
| 4 | NOT NULL (`courses.teacher_id`) | `INSERT INTO courses (teacher_id, title, price) VALUES (NULL, 'Курс без автора', 500.00);` | `null value in column "teacher_id" of relation "courses" violates not-null constraint` | «Нельзя создать курс без преподавателя: у каждого курса должен быть автор» | Передать `teacher_id` существующего преподавателя |
| 5 | FOREIGN KEY, `ON DELETE RESTRICT` (`fk_courses_teacher`) | `DELETE FROM users WHERE user_id = 1;` | `update or delete on table "users" violates foreign key constraint "fk_courses_teacher" on table "courses"` | «Нельзя удалить преподавателя, у которого есть курсы» | Сначала передать его курсы другому преподавателю (`UPDATE courses SET teacher_id = ...`) или удалить курсы, затем удалять пользователя |

> Точный текст `SQLERRM` может немного отличаться в зависимости от версии PostgreSQL (например, в версии 18 в сообщение NOT NULL добавляется имя ограничения). Приведённые сообщения получены на PostgreSQL 16.

### Краткие выводы

1. Ограничения целостности переносят бизнес-правила (оценка 1–5, один студент — одна запись на курс, у курса всегда есть автор) на уровень СУБД. Некорректные данные не попадут в БД, даже если ошибка допущена в приложении.
2. Разные типы ограничений защищают от разных ошибок: `CHECK` — от недопустимых значений, `FOREIGN KEY` — от «висячих» ссылок, `UNIQUE` — от дублей, `NOT NULL` — от пропущенных обязательных данных, `ON DELETE RESTRICT` — от случайного удаления связанных данных.
3. Связь M:N «курс ↔ категория» реализована связующей таблицей с составным PK. Выбор политик `CASCADE` для курса и `RESTRICT` для категории защищает основные данные и позволяет автоматически убирать только «служебные» связи.
4. `ON DELETE CASCADE` удаляет строки, а `DROP TABLE ... CASCADE` удаляет объекты схемы (FK, представления), но не данные зависимых таблиц.
5. Индексы подобраны под 5 типовых запросов: частичные (`WHERE is_published`, `WHERE is_completed`) уменьшают размер индекса, покрывающие (`INCLUDE`, `(course_id, rating)`) позволяют обойтись без чтения таблицы, а дублирующие индексы удалены, чтобы не тормозить запись.
