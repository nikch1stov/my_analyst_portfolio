/* Проект первого модуля: анализ данных для агентства недвижимости
 * Часть 2. Решаем ad hoc задачи
 *
 * Автор: Чистов Николай
 * Дата: 31.01.26
*/

-- Задача 1: Время активности объявлений
-- Пороговые значения перцентилей для фильтрации выбросов
WITH limits AS (
    SELECT  
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY total_area) AS total_area_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY rooms) AS rooms_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY balcony) AS balcony_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_h,
        PERCENTILE_DISC(0.01) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_l
    FROM real_estate.flats     
),
-- ID объявлений без аномальных значений
filtered_id AS(
    SELECT id
    FROM real_estate.flats  
    WHERE 
        total_area < (SELECT total_area_limit FROM limits)
        AND (rooms < (SELECT rooms_limit FROM limits) OR rooms IS NULL)
        AND (balcony < (SELECT balcony_limit FROM limits) OR balcony IS NULL)
        AND ((ceiling_height < (SELECT ceiling_height_limit_h FROM limits)
            AND ceiling_height > (SELECT ceiling_height_limit_l FROM limits)) OR ceiling_height IS NULL)
),
-- Подготовка данных: регион, категория активности и базовые параметры квартир
my_cte AS (
    SELECT
        CASE
  			WHEN f.city_id = '6X8I' THEN 'Санкт-Петербург'
  			ELSE 'ЛенОбл'
        END AS region,
        CASE
            WHEN a.days_exposition IS NULL THEN 'non category'
            WHEN a.days_exposition BETWEEN 1 AND 30  THEN '1-30 days'
            WHEN a.days_exposition BETWEEN 31 AND 90 THEN '31-90 days'
            WHEN a.days_exposition BETWEEN 91 AND 180 THEN '91-180 days'
            WHEN a.days_exposition >= 181 THEN '181+ days'
            ELSE 'non category'
        END AS period,
        a.last_price,
        f.total_area,
        f.rooms,
        f.balcony,
        f.floors_total
    FROM real_estate.flats AS f
    JOIN real_estate.advertisement AS a ON a.id = f.id
    JOIN real_estate.TYPE AS t ON t.type_id = f.type_id
    WHERE
        f.id IN (SELECT id FROM filtered_id)
        AND t.type = 'город'
        AND a.first_day_exposition >= DATE '2015-01-01'
        AND a.first_day_exposition <  DATE '2019-01-01'
)
-- Итоговая сводная таблица по времени активности объявлений в разрезе регионов
SELECT
    region AS "Регион",
    period AS "Категория по времени активности",
    COUNT(*) AS "Количество объявлений",
    ROUND((COUNT(*)::numeric / SUM(COUNT(*)) OVER (PARTITION BY region)) * 100,2) AS "Доля объявлений в регионе, %",
    ROUND(AVG(last_price / NULLIF(total_area, 0))::numeric, 2) AS "Средняя цена квадратного метра",
    ROUND(AVG(total_area)::numeric, 2) AS "Средняя площадь квартиры",
    ROUND(AVG(rooms)::numeric) AS "Среднее количество комнат",
    ROUND(AVG(balcony)::numeric) AS "Среднее количество балконов",
    PERCENTILE_DISC(0.5) WITHIN GROUP (ORDER BY rooms) AS "Медианное количество комнат",
    PERCENTILE_DISC(0.5) WITHIN GROUP (ORDER BY balcony) AS "Медианное количество балконов",
    PERCENTILE_DISC(0.5) WITHIN GROUP (ORDER BY floors_total) AS "Медианное кол-во этажей в доме"
FROM my_cte
GROUP BY region, period
ORDER BY region DESC, period;

-- Задача 2: Сезонность объявлений
-- Пороговые значения перцентилей для фильтрации выбросов
WITH limits AS (
    SELECT  
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY total_area) AS total_area_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY rooms) AS rooms_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY balcony) AS balcony_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_h,
        PERCENTILE_DISC(0.01) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_l
    FROM real_estate.flats     
),
-- ID объявлений без аномальных значений
filtered_id AS(
    SELECT id
    FROM real_estate.flats  
    WHERE 
        total_area < (SELECT total_area_limit FROM limits)
        AND (rooms < (SELECT rooms_limit FROM limits) OR rooms IS NULL)
        AND (balcony < (SELECT balcony_limit FROM limits) OR balcony IS NULL)
        AND ((ceiling_height < (SELECT ceiling_height_limit_h FROM limits)
        AND ceiling_height > (SELECT ceiling_height_limit_l FROM limits)) OR ceiling_height IS NULL)
    ),
-- Подготовка чистых объявлений для анализа сезонности
clear_ads AS (
    SELECT
        f.id AS id,
        a.first_day_exposition,
        a.days_exposition,
        a.first_day_exposition + (a.days_exposition * interval '1 day') AS finish_date,
        DATE_TRUNC('month', a.first_day_exposition)::date AS pub_month,
        DATE_TRUNC('month', a.first_day_exposition + (a.days_exposition * interval '1 day'))::date AS close_month,
        a.last_price / NULLIF(f.total_area, 0) AS price_m2,
        f.total_area
    FROM real_estate.flats AS f
    JOIN real_estate.type AS t ON f.type_id = t.type_id
    JOIN real_estate.advertisement AS a ON a.id = f.id
    WHERE
        f.id IN (SELECT id FROM filtered_id)
        AND t.type = 'город'
        AND a.first_day_exposition >= DATE '2015-01-01'
        AND a.first_day_exposition <  DATE '2019-01-01'
),
-- Статистика по месяцу публикации объявлений
publish AS (
    SELECT
        EXTRACT(MONTH FROM pub_month)::int AS month_num,
        TRIM(TO_CHAR(pub_month, 'Month')) AS month_name,
        COUNT(*) AS published_cnt,
        ROUND(AVG(price_m2)::numeric, 2) AS avg_price_m2_pub,
        ROUND(AVG(total_area)::numeric, 2) AS avg_total_area_pub
    FROM clear_ads
    GROUP BY month_num, month_name
),
-- Статистика по месяцу снятия объявлений
close AS (
    SELECT
        EXTRACT(MONTH FROM close_month)::int AS month_num,
        TRIM(TO_CHAR(close_month, 'Month')) AS month_name,
        COUNT(*) AS closed_cnt,
        ROUND(AVG(price_m2)::numeric, 2) AS avg_price_m2_close,
        ROUND(AVG(total_area)::numeric, 2) AS avg_total_area_close
    FROM clear_ads
    WHERE close_month IS NOT NULL
      AND close_month >= DATE '2015-01-01'
      AND close_month <  DATE '2019-01-01'
    GROUP BY month_num, month_name
)
-- Итоговая таблица сезонности публикаций и снятий
SELECT
    COALESCE(p.month_name, c.month_name) AS "Месяц",
    COALESCE(p.published_cnt, 0) AS "Публикации (шт)",
    COALESCE(c.closed_cnt, 0) AS "Снятия (шт)",
    ROUND(COALESCE(p.published_cnt, 0)::numeric/ NULLIF(SUM(COALESCE(p.published_cnt, 0)) OVER (), 0) * 100,2) AS "Доля публикаций, %",
    ROUND(COALESCE(c.closed_cnt, 0)::numeric/ NULLIF(SUM(COALESCE(c.closed_cnt, 0)) OVER (), 0) * 100,2) AS "Доля снятий, %",
    RANK() OVER (ORDER BY COALESCE(p.published_cnt, 0) DESC) AS "Ранг по публикациям",
    RANK() OVER (ORDER BY COALESCE(c.closed_cnt, 0) DESC) AS "Ранг по снятиям",
    p.avg_price_m2_pub AS "Средняя цена м² (публикация)",
    c.avg_price_m2_close AS "Средняя цена м² (снятие)",
    p.avg_total_area_pub AS "Средняя площадь (публикация)",
    c.avg_total_area_close AS "Средняя площадь (снятие)"
FROM publish AS p
FULL JOIN close AS c ON p.month_num = c.month_num
ORDER BY COALESCE(p.month_num, c.month_num);

