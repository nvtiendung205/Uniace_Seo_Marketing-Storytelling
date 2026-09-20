-- Chuyển đổi từ vãng lai sang tiềm năng
-- email/ip=ip+email without ip
WITH combined AS (SELECT ID, IP_Address, Datetime, Email FROM uniace_1
  UNION ALL
  SELECT ID, IP_Address, Datetime, Email FROM uniace_2
  UNION ALL
  SELECT ID, IP_Address, Datetime, Email FROM uniace_3
),
prep AS (SELECT STR_TO_DATE(Datetime, '%Y-%m-%d %H:%i:%s') AS dt,
    LOWER(TRIM(Email)) AS email_norm,
    TRIM(IP_Address) AS ip_norm
  FROM combined
  WHERE Datetime IS NOT NULL
),
stats AS (SELECT DATE(dt) AS date_day,
    -- TỬ SỐ: số email duy nhất trong ngày
    COUNT(DISTINCT email_norm) AS total_email,
    -- MẪU SỐ: IP nếu có, nếu không thì dùng email thay thế
    COUNT(DISTINCT
      CASE
        WHEN ip_norm IS NOT NULL THEN ip_norm
        WHEN ip_norm IS NULL AND email_norm IS NOT NULL THEN CONCAT('email:', email_norm)
        ELSE NULL
      END
    ) AS total_user
  FROM prep
  GROUP BY DATE(dt)
)
SELECT date_day,
  total_email,
  total_user,
  ROUND(total_email * 100.0 / NULLIF(total_user, 0), 2) AS conversion_rate
FROM stats
ORDER BY date_day;


-- Chuyển đổi từ khách hàng tiềm năng sang mua
WITH combined AS (SELECT ID, Datetime, Name, Email
    FROM uniace_1
    UNION ALL
    SELECT ID, Datetime, Name, Email
    FROM uniace_2
    UNION ALL
    SELECT ID, Datetime, Name, Email
    FROM uniace_3
),

prep AS (SELECT ID,
        CASE
            WHEN STR_TO_DATE(Datetime, '%Y-%m-%d %H:%i:%s') IS NOT NULL
                THEN DATE(STR_TO_DATE(Datetime, '%Y-%m-%d %H:%i:%s'))
            ELSE NULL
        END AS date_ok,
        LOWER(TRIM(Name))  AS name_norm,
        LOWER(TRIM(Email)) AS email_norm
    FROM combined
    WHERE Email IS NOT NULL
),

with_neighbors AS (SELECT ID, date_ok, name_norm, email_norm,
                          LAG(date_ok)  OVER (ORDER BY ID) AS prev_day,
                          LEAD(date_ok) OVER (ORDER BY ID) AS next_day
                    FROM prep
),

filled AS (SELECT ID,
        CASE
            WHEN date_ok IS NOT NULL THEN date_ok
            WHEN prev_day IS NULL THEN next_day
            WHEN next_day IS NULL THEN prev_day
            WHEN ABS(DATEDIFF(next_day, prev_day)) = 0 THEN prev_day
            ELSE
                CASE
                    WHEN ABS(DATEDIFF(COALESCE(prev_day,next_day), CURDATE()))
                         <= ABS(DATEDIFF(COALESCE(next_day,prev_day), CURDATE()))
                    THEN prev_day ELSE next_day
                END
        END AS date_filled,
        name_norm,
        email_norm
    FROM with_neighbors
)

SELECT date_filled,
    COUNT(DISTINCT email_norm) AS total_user,
    COUNT(DISTINCT CASE WHEN name_norm = 'completed order' THEN email_norm END) AS total_user_order,
    ROUND(
        COUNT(DISTINCT CASE WHEN name_norm = 'completed order' THEN email_norm END) * 100.0
        / NULLIF(COUNT(DISTINCT email_norm),0), 2
    ) AS conversion_rate
FROM filled
WHERE date_filled IS NOT NULL
GROUP BY date_filled
ORDER BY date_filled;


-- Returning: khách quay lại

WITH combined AS (SELECT IP_Address,
        STR_TO_DATE(Datetime, '%Y-%m-%d %H:%i:%s') AS dt
    FROM uniace_1
    WHERE IP_Address IS NOT NULL AND Datetime IS NOT NULL

    UNION ALL

    SELECT
        IP_Address,
        STR_TO_DATE(Datetime, '%Y-%m-%d %H:%i:%s') AS dt
    FROM uniace_2
    WHERE IP_Address IS NOT NULL AND Datetime IS NOT NULL

    UNION ALL

    SELECT IP_Address,
        STR_TO_DATE(Datetime, '%Y-%m-%d %H:%i:%s') AS dt
    FROM uniace_3
    WHERE IP_Address IS NOT NULL AND Datetime IS NOT NULL
),
first_visit AS (
    SELECT IP_Address,
        MIN(DATE(dt)) AS first_date
    FROM combined
    GROUP BY IP_Address
),
returning_visits AS (SELECT c.IP_Address,
        DATE(c.dt) AS visit_date
    FROM combined c
    JOIN first_visit f ON c.IP_Address = f.IP_Address
    WHERE DATE(c.dt) > f.first_date
),
returning_summary AS (SELECT IP_Address, COUNT(DISTINCT visit_date) AS returning_days
    FROM returning_visits
    GROUP BY IP_Address
)
SELECT IP_Address, returning_days
FROM returning_summary
ORDER BY returning_days DESC;

