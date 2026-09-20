-- 0. Очистка таблиц с каскадным удалением связей (для повторного запуска)
DROP TABLE IF EXISTS lesson_progress CASCADE;
DROP TABLE IF EXISTS reviews CASCADE;
DROP TABLE IF EXISTS enrollments CASCADE;
DROP TABLE IF EXISTS lessons CASCADE;
DROP TABLE IF EXISTS courses CASCADE;
DROP TABLE IF EXISTS users CASCADE;

-- 1. Таблица пользователей
CREATE TABLE users (
    user_id SERIAL PRIMARY KEY,
    full_name VARCHAR(150) NOT NULL,
    email VARCHAR(255) NOT NULL UNIQUE,
    password_hash VARCHAR(255) NOT NULL,
    role VARCHAR(20) NOT NULL CHECK (role IN ('student', 'teacher', 'admin')),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL
);

-- 2. Таблица курсов
CREATE TABLE courses (
    course_id SERIAL PRIMARY KEY,
    teacher_id INTEGER NOT NULL,
    title VARCHAR(200) NOT NULL,
    description TEXT,
    price DECIMAL(10, 2) NOT NULL CHECK (price >= 0),
    is_published BOOLEAN DEFAULT FALSE NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT fk_courses_teacher FOREIGN KEY (teacher_id) 
        REFERENCES users(user_id) ON DELETE RESTRICT
);

-- 3. Таблица уроков
CREATE TABLE lessons (
    lesson_id SERIAL PRIMARY KEY,
    course_id INTEGER NOT NULL,
    title VARCHAR(200) NOT NULL,
    content_url TEXT,
    order_number INTEGER NOT NULL CHECK (order_number > 0),
    duration_minutes INTEGER CHECK (duration_minutes > 0),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT fk_lessons_course FOREIGN KEY (course_id) 
        REFERENCES courses(course_id) ON DELETE CASCADE,
    CONSTRAINT uq_course_order UNIQUE (course_id, order_number)
);

-- 4. Таблица записей на курсы (Enrollments)
CREATE TABLE enrollments (
    enrollment_id SERIAL PRIMARY KEY,
    student_id INTEGER NOT NULL,
    course_id INTEGER NOT NULL,
    price_paid DECIMAL(10, 2) NOT NULL CHECK (price_paid >= 0),
    enrolled_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL,
    status VARCHAR(20) DEFAULT 'active' NOT NULL CHECK (status IN ('active', 'completed', 'refunded')),
    CONSTRAINT fk_enrollments_student FOREIGN KEY (student_id) 
        REFERENCES users(user_id) ON DELETE CASCADE,
    CONSTRAINT fk_enrollments_course FOREIGN KEY (course_id) 
        REFERENCES courses(course_id) ON DELETE RESTRICT,
    CONSTRAINT uq_student_course UNIQUE (student_id, course_id)
);

-- 5. Таблица отзывов
CREATE TABLE reviews (
    review_id SERIAL PRIMARY KEY,
    student_id INTEGER NOT NULL,
    course_id INTEGER NOT NULL,
    rating INTEGER NOT NULL CHECK (rating BETWEEN 1 AND 5),
    comment TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT fk_reviews_student FOREIGN KEY (student_id) 
        REFERENCES users(user_id) ON DELETE CASCADE,
    CONSTRAINT fk_reviews_course FOREIGN KEY (course_id) 
        REFERENCES courses(course_id) ON DELETE CASCADE,
    CONSTRAINT uq_student_course_review UNIQUE (student_id, course_id)
);

-- 6. Таблица прогресса прохождения уроков
CREATE TABLE lesson_progress (
    progress_id SERIAL PRIMARY KEY,
    enrollment_id INTEGER NOT NULL,
    lesson_id INTEGER NOT NULL,
    is_completed BOOLEAN DEFAULT FALSE NOT NULL,
    completed_at TIMESTAMP WITH TIME ZONE,
    CONSTRAINT fk_progress_enrollment FOREIGN KEY (enrollment_id) 
        REFERENCES enrollments(enrollment_id) ON DELETE CASCADE,
    CONSTRAINT fk_progress_lesson FOREIGN KEY (lesson_id) 
        REFERENCES lessons(lesson_id) ON DELETE CASCADE,
    CONSTRAINT uq_enrollment_lesson UNIQUE (enrollment_id, lesson_id)
);


-- Индексы для внешних ключей (повышают скорость выполнения JOIN запросов)

CREATE INDEX idx_courses_teacher_id ON courses(teacher_id);
CREATE INDEX idx_lessons_course_id ON lessons(course_id);
CREATE INDEX idx_enrollments_student_id ON enrollments(student_id);
CREATE INDEX idx_enrollments_course_id ON enrollments(course_id);
CREATE INDEX idx_reviews_student_id ON reviews(student_id);
CREATE INDEX idx_reviews_course_id ON reviews(course_id);
CREATE INDEX idx_progress_enrollment_id ON lesson_progress(enrollment_id);
CREATE INDEX idx_progress_lesson_id ON lesson_progress(lesson_id);