-- name: aggregate-logs
SELECT
    severity,
    message,
    first(revision, creation_timestamp) AS min_revision,
    last(revision, creation_timestamp) AS max_revision,
    min(creation_timestamp) AS min_creation_timestamp,
    max(creation_timestamp) AS max_creation_timestamp,
    count(*) AS count
FROM log
WHERE
    sensor_identifier = ${sensor_identifier} AND severity = any(
        ARRAY['warning', 'error']
    )
GROUP BY sensor_identifier, severity, message
ORDER BY max_creation_timestamp ASC;


-- name: aggregate-network
-- Aggregate information about sensors
WITH aggregation AS (
    SELECT
        sensor_identifier,
        array_agg(bucket_timestamp) AS bucket_timestamps,
        array_agg(measurement_count) AS measurement_counts
    FROM measurement_aggregation_4_hours
    WHERE bucket_timestamp > now() - INTERVAL '28 days'
    GROUP BY sensor_identifier
)
-- Filter by sensors belonging to the given network
SELECT
    sensor.identifier AS sensor_identifier,
    sensor.name AS sensor_name,
    coalesce(
        aggregation.bucket_timestamps, ARRAY[]::TIMESTAMPTZ []
    ) AS bucket_timestamps,
    coalesce(
        aggregation.measurement_counts, ARRAY[]::INT []
    ) AS measurement_counts
FROM network
INNER JOIN sensor ON network.identifier = sensor.network_identifier
LEFT JOIN aggregation ON sensor.identifier = aggregation.sensor_identifier
WHERE network.identifier = ${network_identifier};


-- name: create-network
INSERT INTO network (
    identifier,
    name,
    creation_timestamp
)
VALUES (
    uuid_generate_v4(),
    ${network_name},
    now()
)
RETURNING identifier AS network_identifier;


-- name: read-networks
SELECT
    network.identifier AS network_identifier,
    network.name AS network_name
FROM permission
INNER JOIN network ON permission.network_identifier = network.identifier
WHERE user_identifier = ${user_identifier};


-- name: create-permission
INSERT INTO permission (
    user_identifier,
    network_identifier,
    creation_timestamp
)
VALUES (
    ${user_identifier},
    ${network_identifier},
    now()
);


-- name: create-log
INSERT INTO log (
    sensor_identifier,
    severity,
    message,
    revision,
    creation_timestamp,
    receipt_timestamp
)
VALUES (
    ${sensor_identifier},
    ${severity},
    ${message},
    ${revision},
    ${creation_timestamp},
    now()
);


-- name: create-measurement
INSERT INTO measurement (
    sensor_identifier,
    attribute,
    value,
    revision,
    creation_timestamp,
    receipt_timestamp
)
VALUES (
    ${sensor_identifier},
    ${attribute},
    ${value},
    ${revision},
    ${creation_timestamp},
    now()
);


-- name: create-sensor
INSERT INTO sensor (
    identifier,
    name,
    network_identifier,
    creation_timestamp
)
VALUES (
    uuid_generate_v4(),
    ${sensor_name},
    ${network_identifier},
    now()
)
RETURNING identifier AS sensor_identifier;


-- name: create-session
INSERT INTO session (
    access_token_hash,
    user_identifier,
    creation_timestamp
)
VALUES (
    ${access_token_hash},
    ${user_identifier},
    now()
);


-- name: create-user
INSERT INTO "user" (
    identifier,
    name,
    creation_timestamp,
    password_hash
)
VALUES (
    uuid_generate_v4(),
    ${user_name},
    now(),
    ${password_hash}
)
RETURNING identifier AS user_identifier;


-- name: read-configurations
SELECT
    value,
    revision,
    creation_timestamp,
    publication_timestamp,
    acknowledgment_timestamp,
    receipt_timestamp,
    success
FROM configuration
WHERE
    sensor_identifier = ${sensor_identifier}
    AND CASE
        WHEN ${revision}::INT IS NOT NULL
            THEN (
                CASE
                    WHEN ${direction} = 'next'
                        THEN revision > ${revision}
                    WHEN ${direction} = 'previous'
                        THEN revision < ${revision}
                    ELSE TRUE
                END
            )
        ELSE TRUE
    END
ORDER BY
    CASE WHEN ${direction} = 'next' THEN revision END ASC,
    CASE WHEN ${direction} = 'previous' THEN revision END DESC
LIMIT 64;


-- name: read-measurements
-- Assemble data points that have the same timestamp and revision
-- back into measurements, then sort and paginate
SELECT
    revision,
    creation_timestamp,
    jsonb_object_agg(attribute, value) AS value
FROM measurement
WHERE
    sensor_identifier = ${sensor_identifier}
    AND CASE
        WHEN ${creation_timestamp}::TIMESTAMPTZ IS NOT NULL
            THEN (
                CASE
                    WHEN ${direction} = 'next'
                        THEN creation_timestamp > ${creation_timestamp}
                    WHEN ${direction} = 'previous'
                        THEN creation_timestamp < ${creation_timestamp}
                    ELSE TRUE
                END
            )
        ELSE TRUE
    END
GROUP BY revision, creation_timestamp
ORDER BY
    CASE WHEN ${direction} = 'next' THEN creation_timestamp END ASC,
    CASE WHEN ${direction} = 'previous' THEN creation_timestamp END DESC
LIMIT 64;


-- name: read-logs
SELECT
    severity,
    message,
    revision,
    creation_timestamp
FROM log
WHERE
    sensor_identifier = ${sensor_identifier}
    AND CASE
        WHEN ${creation_timestamp}::TIMESTAMPTZ IS NOT NULL
            THEN (
                CASE
                    WHEN ${direction} = 'next'
                        THEN creation_timestamp > ${creation_timestamp}
                    WHEN ${direction} = 'previous'
                        THEN creation_timestamp < ${creation_timestamp}
                    ELSE TRUE
                END
            )
        ELSE TRUE
    END
ORDER BY
    CASE WHEN ${direction} = 'next' THEN creation_timestamp END ASC,
    CASE WHEN ${direction} = 'previous' THEN creation_timestamp END DESC
LIMIT 64;


-- name: read-user
SELECT
    identifier AS user_identifier,
    password_hash
FROM "user"
WHERE name = ${user_name};


-- name: authenticate
SELECT user_identifier
FROM session
WHERE access_token_hash = ${access_token_hash};


-- name: authorize-resource-network
-- Return no elements if the network doesn't exist and NULL if permissions are missing
-- Could be extended to support finer grained permission relationships
WITH interim AS (
    SELECT
        user_identifier,
        network_identifier
    FROM permission
    WHERE user_identifier = ${user_identifier}
)
SELECT interim.user_identifier
FROM network
LEFT JOIN interim ON network.identifier = interim.network_identifier
WHERE network.identifier = ${network_identifier};


-- name: authorize-resource-sensor
-- Return no elements if the network or sensor doesn't exist and NULL if permissions are missing
-- Could be extended to support finer grained permission relationships
WITH interim AS (
    SELECT
        user_identifier,
        network_identifier
    FROM permission
    WHERE user_identifier = ${user_identifier}
)
SELECT interim.user_identifier
FROM sensor
LEFT JOIN interim USING (network_identifier)
WHERE
    sensor.network_identifier = ${network_identifier}
    AND sensor.identifier = ${sensor_identifier};


-- name: create-configuration
INSERT INTO configuration (
    sensor_identifier,
    revision,
    creation_timestamp,
    value
)
VALUES (
    ${sensor_identifier},
    (
        SELECT coalesce(max(revision) + 1, 0)
        FROM configuration
        WHERE sensor_identifier = ${sensor_identifier}
    ),
    now(),
    ${configuration}
)
RETURNING revision;


-- name: update-configuration-on-publication
UPDATE configuration
SET publication_timestamp = now()
WHERE
    sensor_identifier = ${sensor_identifier}
    AND revision = ${revision}
    AND publication_timestamp IS NULL;


-- name: update-configuration-on-acknowledgment
UPDATE configuration
SET
    acknowledgment_timestamp = ${acknowledgment_timestamp},
    receipt_timestamp = now(),
    success = ${success}
WHERE
    sensor_identifier = ${sensor_identifier}
    AND revision = ${revision}
    AND acknowledgment_timestamp IS NULL;


-- name: update-sensor
UPDATE sensor
SET name = ${sensor_name}
WHERE identifier = ${sensor_identifier};
