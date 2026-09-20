-- =====================================================================
-- ДЗ №2. Часть 1. Дополнение схемы (EdTech)
-- Студент: Раднаев Зоригто Батоевич, группа ДЭ 15-25
-- Запускать ПОСЛЕ schema.sql из ДЗ №1. Скрипт можно запускать повторно.
-- =====================================================================

BEGIN;

-- ---------------------------------------------------------------------
-- 0. Очистка новых таблиц (для повторного запуска)
-- ---------------------------------------------------------------------
DROP TABLE IF EXISTS course_categories CASCADE;
DROP TABLE IF EXISTS categories CASCADE;

-- ---------------------------------------------------------------------
-- 1. НОВАЯ ТАБЛИЦА: categories (справочник категорий курсов)
-- ---------------------------------------------------------------------
CREATE TABLE categories (
    category_id SERIAL PRIMARY KEY,
    name        VARCHAR(100) NOT NULL,
    slug        VARCHAR(100) NOT NULL,
    description TEXT,
    created_at  TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT uq_categories_name UNIQUE (name),
    CONSTRAINT uq_categories_slug UNIQUE (slug),
    CONSTRAINT chk_categories_name_not_blank CHECK (length(trim(name)) > 0),
    -- slug: только латиница в нижнем регистре, цифры и дефисы (для URL)
    CONSTRAINT chk_categories_slug_format CHECK (slug ~ '^[a-z0-9]+(-[a-z0-9]+)*$')
);

-- ---------------------------------------------------------------------
-- 2. НОВАЯ ТАБЛИЦА: course_categories (связующая таблица для M:N)
--    Курс может относиться к нескольким категориям,
--    в категории может быть много курсов.
-- ---------------------------------------------------------------------
CREATE TABLE course_categories (
    course_id   INTEGER NOT NULL,
    category_id INTEGER NOT NULL,
    is_primary  BOOLEAN DEFAULT FALSE NOT NULL,
    assigned_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL,
    -- Составной PK: одна и та же пара (курс, категория) не может повторяться
    CONSTRAINT pk_course_categories PRIMARY KEY (course_id, category_id),
    -- Удаляется курс -> удаляются только его "ярлыки" категорий
    CONSTRAINT fk_cc_course FOREIGN KEY (course_id)
        REFERENCES courses(course_id) ON DELETE CASCADE,
    -- Категорию с курсами удалить нельзя: сначала нужно перенести курсы
    CONSTRAINT fk_cc_category FOREIGN KEY (category_id)
        REFERENCES categories(category_id) ON DELETE RESTRICT
);

-- Обратный поиск "все курсы категории" (PK начинается с course_id и его не покрывает)
CREATE INDEX idx_cc_category_course ON course_categories (category_id, course_id);

-- Не более одной основной категории у курса
CREATE UNIQUE INDEX uq_cc_one_primary_per_course
    ON course_categories (course_id) WHERE is_primary;

-- ---------------------------------------------------------------------
-- 3. Дополнительные ограничения бизнес-логики для СУЩЕСТВУЮЩИХ таблиц
-- ---------------------------------------------------------------------

-- Формат e-mail
ALTER TABLE users DROP CONSTRAINT IF EXISTS chk_users_email_format;
ALTER TABLE users ADD CONSTRAINT chk_users_email_format
    CHECK (email ~* '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$');

-- Урок "пройден" тогда и только тогда, когда указана дата прохождения
ALTER TABLE lesson_progress DROP CONSTRAINT IF EXISTS chk_progress_completed_consistency;
ALTER TABLE lesson_progress ADD CONSTRAINT chk_progress_completed_consistency
    CHECK (is_completed = (completed_at IS NOT NULL));

-- ---------------------------------------------------------------------
-- 4. ИНДЕКСЫ под частые запросы из ДЗ №1
-- ---------------------------------------------------------------------

-- Запрос 1 (каталог): опубликованные курсы, новые сверху.
-- Частичный индекс: неопубликованные курсы в него не попадают.
CREATE INDEX IF NOT EXISTS idx_courses_published
    ON courses (created_at DESC) WHERE is_published;

-- Запросы 1 и 2 (средний рейтинг, топ-10): AVG(rating) и COUNT(*) по course_id
-- берутся из индекса без обращения к таблице (index-only scan).
-- Заменяет idx_reviews_course_id.
DROP INDEX IF EXISTS idx_reviews_course_id;
CREATE INDEX IF NOT EXISTS idx_reviews_course_rating
    ON reviews (course_id, rating);

-- Запрос 5 (доход преподавателя за месяц): фильтр по course_id + диапазон дат,
-- price_paid и status лежат в индексе (INCLUDE).
-- Остаётся пригодным и для проверки FK courses -> enrollments (ON DELETE RESTRICT).
-- Заменяет idx_enrollments_course_id.
DROP INDEX IF EXISTS idx_enrollments_course_id;
CREATE INDEX IF NOT EXISTS idx_enrollments_course_enrolled
    ON enrollments (course_id, enrolled_at) INCLUDE (price_paid, status);

-- Запрос 4 (процент прохождения): считаем только пройденные уроки записи.
CREATE INDEX IF NOT EXISTS idx_progress_enrollment_completed
    ON lesson_progress (enrollment_id) WHERE is_completed;

-- Удаляем избыточные индексы: их полностью покрывают индексы, которые
-- PostgreSQL автоматически создаёт под UNIQUE-ограничения
-- (ведущий столбец совпадает), а лишние индексы замедляют INSERT/UPDATE.
--   uq_course_order       (course_id, order_number)    -> idx_lessons_course_id  (и запрос 3: уроки курса по order_number)
--   uq_student_course     (student_id, course_id)      -> idx_enrollments_student_id (запрос 4)
--   uq_student_course_review (student_id, course_id)   -> idx_reviews_student_id
--   uq_enrollment_lesson  (enrollment_id, lesson_id)   -> idx_progress_enrollment_id
DROP INDEX IF EXISTS idx_lessons_course_id;
DROP INDEX IF EXISTS idx_enrollments_student_id;
DROP INDEX IF EXISTS idx_reviews_student_id;
DROP INDEX IF EXISTS idx_progress_enrollment_id;

-- Оставлены без изменений (нужны для JOIN и проверки FK):
--   idx_courses_teacher_id, idx_progress_lesson_id

-- ---------------------------------------------------------------------
-- 5. ТЕСТОВЫЕ ДАННЫЕ (нужны для скрипта демонстрации нарушений)
-- ---------------------------------------------------------------------
INSERT INTO users (user_id, full_name, email, password_hash, role) VALUES
    (1, 'Иванов Пётр Сергеевич',    'ivanov@edu.example',  'hash_1', 'teacher'),
    (2, 'Смирнова Анна Олеговна',   'smirnova@edu.example','hash_2', 'teacher'),
    (3, 'Раднаев Зоригто Батоевич', 'zorigto@edu.example', 'hash_3', 'student'),
    (4, 'Петрова Мария Ильинична',  'petrova@edu.example', 'hash_4', 'student')
ON CONFLICT DO NOTHING;

INSERT INTO courses (course_id, teacher_id, title, description, price, is_published) VALUES
    (1, 1, 'SQL для начинающих',     'Базовый курс по SQL',        1990.00, TRUE),
    (2, 2, 'PostgreSQL: оптимизация','Индексы и планы запросов',   4990.00, TRUE),
    (3, 2, 'Черновик курса',         NULL,                            0.00, FALSE)
ON CONFLICT DO NOTHING;

INSERT INTO lessons (lesson_id, course_id, title, order_number, duration_minutes) VALUES
    (1, 1, 'Введение',        1, 15),
    (2, 1, 'SELECT и WHERE',  2, 30),
    (3, 1, 'JOIN',            3, 40),
    (4, 2, 'Типы индексов',   1, 45)
ON CONFLICT DO NOTHING;

INSERT INTO enrollments (enrollment_id, student_id, course_id, price_paid, status) VALUES
    (1, 3, 1, 1990.00, 'active'),
    (2, 3, 2, 4990.00, 'active')
ON CONFLICT DO NOTHING;

INSERT INTO lesson_progress (progress_id, enrollment_id, lesson_id, is_completed, completed_at) VALUES
    (1, 1, 1, TRUE,  CURRENT_TIMESTAMP),
    (2, 1, 2, FALSE, NULL)
ON CONFLICT DO NOTHING;

INSERT INTO reviews (review_id, student_id, course_id, rating, comment) VALUES
    (1, 3, 1, 5, 'Отличный курс')
ON CONFLICT DO NOTHING;

INSERT INTO categories (category_id, name, slug, description) VALUES
    (1, 'Базы данных', 'databases',   'Курсы по SQL и СУБД'),
    (2, 'Программирование', 'programming', 'Курсы по языкам программирования'),
    (3, 'Для начинающих', 'beginners', 'Курсы с нулевого уровня')
ON CONFLICT DO NOTHING;

INSERT INTO course_categories (course_id, category_id, is_primary) VALUES
    (1, 1, TRUE),
    (1, 3, FALSE),
    (2, 1, TRUE)
ON CONFLICT DO NOTHING;

-- Выравниваем SERIAL-последовательности после вставки с явными id
SELECT setval(pg_get_serial_sequence('users','user_id'),                 (SELECT MAX(user_id) FROM users));
SELECT setval(pg_get_serial_sequence('courses','course_id'),             (SELECT MAX(course_id) FROM courses));
SELECT setval(pg_get_serial_sequence('lessons','lesson_id'),             (SELECT MAX(lesson_id) FROM lessons));
SELECT setval(pg_get_serial_sequence('enrollments','enrollment_id'),     (SELECT MAX(enrollment_id) FROM enrollments));
SELECT setval(pg_get_serial_sequence('lesson_progress','progress_id'),   (SELECT MAX(progress_id) FROM lesson_progress));
SELECT setval(pg_get_serial_sequence('reviews','review_id'),             (SELECT MAX(review_id) FROM reviews));
SELECT setval(pg_get_serial_sequence('categories','category_id'),        (SELECT MAX(category_id) FROM categories));

COMMIT;
