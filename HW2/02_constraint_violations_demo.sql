-- =====================================================================
-- ДЗ №2. Часть 2. Демонстрация нарушений ограничений (EdTech)
-- Студент: Раднаев Зоригто Батоевич, группа ДЭ 15-25
-- Перед запуском выполнить: schema.sql, затем 01_schema_additions.sql
-- Каждый блок намеренно вызывает ошибку; данные при этом не меняются
-- (при ошибке PostgreSQL откатывает действия внутри блока).
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. CHECK: оценка отзыва вне диапазона 1..5
-- ---------------------------------------------------------------------
DO $$
DECLARE
    v_constraint TEXT;
BEGIN
    INSERT INTO reviews (student_id, course_id, rating, comment)
    VALUES (4, 1, 7, 'Оценка вне допустимой шкалы');

    RAISE NOTICE '[1] ВНИМАНИЕ: ошибка не возникла, ограничение не сработало!';
EXCEPTION
    WHEN check_violation THEN
        GET STACKED DIAGNOSTICS v_constraint = CONSTRAINT_NAME;
        RAISE NOTICE '[1] CHECK. Оценка курса должна быть целым числом от 1 до 5. Нарушено ограничение: %. Текст ошибки СУБД: %',
            v_constraint, SQLERRM;
    WHEN others THEN
        RAISE NOTICE '[1] Неожиданная ошибка (%): %', SQLSTATE, SQLERRM;
END;
$$;

-- ---------------------------------------------------------------------
-- 2. FOREIGN KEY: запись на несуществующий курс
-- ---------------------------------------------------------------------
DO $$
DECLARE
    v_constraint TEXT;
BEGIN
    INSERT INTO enrollments (student_id, course_id, price_paid)
    VALUES (4, 999, 1000.00);

    RAISE NOTICE '[2] ВНИМАНИЕ: ошибка не возникла, ограничение не сработало!';
EXCEPTION
    WHEN foreign_key_violation THEN
        GET STACKED DIAGNOSTICS v_constraint = CONSTRAINT_NAME;
        RAISE NOTICE '[2] FOREIGN KEY. Нельзя записаться на курс, которого не существует (course_id = 999). Нарушено ограничение: %. Текст ошибки СУБД: %',
            v_constraint, SQLERRM;
    WHEN others THEN
        RAISE NOTICE '[2] Неожиданная ошибка (%): %', SQLSTATE, SQLERRM;
END;
$$;

-- ---------------------------------------------------------------------
-- 3. UNIQUE: повторная запись студента на тот же курс
--    (студент 3 уже записан на курс 1)
-- ---------------------------------------------------------------------
DO $$
DECLARE
    v_constraint TEXT;
BEGIN
    INSERT INTO enrollments (student_id, course_id, price_paid)
    VALUES (3, 1, 1990.00);

    RAISE NOTICE '[3] ВНИМАНИЕ: ошибка не возникла, ограничение не сработало!';
EXCEPTION
    WHEN unique_violation THEN
        GET STACKED DIAGNOSTICS v_constraint = CONSTRAINT_NAME;
        RAISE NOTICE '[3] UNIQUE. Студент уже записан на этот курс, повторно купить его нельзя. Нарушено ограничение: %. Текст ошибки СУБД: %',
            v_constraint, SQLERRM;
    WHEN others THEN
        RAISE NOTICE '[3] Неожиданная ошибка (%): %', SQLSTATE, SQLERRM;
END;
$$;

-- ---------------------------------------------------------------------
-- 4. NOT NULL: курс без преподавателя
-- ---------------------------------------------------------------------
DO $$
DECLARE
    v_column TEXT;
BEGIN
    INSERT INTO courses (teacher_id, title, price)
    VALUES (NULL, 'Курс без автора', 500.00);

    RAISE NOTICE '[4] ВНИМАНИЕ: ошибка не возникла, ограничение не сработало!';
EXCEPTION
    WHEN not_null_violation THEN
        GET STACKED DIAGNOSTICS v_column = COLUMN_NAME;
        RAISE NOTICE '[4] NOT NULL. Нельзя создать курс без преподавателя: у каждого курса должен быть автор. Проблемная колонка: %. Текст ошибки СУБД: %',
            v_column, SQLERRM;
    WHEN others THEN
        RAISE NOTICE '[4] Неожиданная ошибка (%): %', SQLSTATE, SQLERRM;
END;
$$;

-- ---------------------------------------------------------------------
-- 5. Другое: FOREIGN KEY ... ON DELETE RESTRICT
--    Удаление преподавателя, у которого есть курсы
-- ---------------------------------------------------------------------
DO $$
DECLARE
    v_constraint TEXT;
BEGIN
    DELETE FROM users WHERE user_id = 1;

    RAISE NOTICE '[5] ВНИМАНИЕ: ошибка не возникла, ограничение не сработало!';
EXCEPTION
    WHEN foreign_key_violation THEN
        GET STACKED DIAGNOSTICS v_constraint = CONSTRAINT_NAME;
        RAISE NOTICE '[5] ON DELETE RESTRICT. Нельзя удалить преподавателя, у которого есть курсы: сначала нужно передать или удалить его курсы. Нарушено ограничение: %. Текст ошибки СУБД: %',
            v_constraint, SQLERRM;
    WHEN others THEN
        RAISE NOTICE '[5] Неожиданная ошибка (%): %', SQLSTATE, SQLERRM;
END;
$$;
