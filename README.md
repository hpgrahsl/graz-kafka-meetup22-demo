# Client-Side Field Level Cryptography for Streaming Data Pipelines

All services for this demo scenario are pre-configured and supposed to be run using the provided docker compose environment. The `docker-compose.yaml` file references container images for **arm64 CPUs**. Make sure to change them accordingly if you plan to run this on a different CPU architecture.

_NOTE: The following commands are supposed to be run from within the root directory of this repository._

### 0. Start 🐳 Docker Compose Environment

Running `docker compose up` starts the following services:

* connect
* kafka
* ksqldb-cli
* ksqldb-server
* minio
* mongodb
* schema-registry
* zookeeper

### 1. 🔎 Inspect original MongoDB 🍃 { documents } in `demodb.fake_citizens` collection

In a separate terminal window run 

```
docker run -it --rm \
        --network sample-scenario \
        mongo:6.0.1 \
        mongosh mongodb:27017/demodb --eval "db.getCollection('fake_citizens').find().limit(10)"
```

This should result in displaying the documents contained in the corresponding MongoDB collection `demodb.fake_citizens`. One such document looks as follows:

```json
{
    "_id": "6326f8ae1906fc47bc20248f",
    "personal": {
      "firstname": "Darla",
      "lastname": "Moore",
      "age": 32,
      "eyecolor": "hazel",
      "gender": "female",
      "height": 155,
      "weight": 126
    },
    "isactive": false,
    "registered": "2021-06-10T07:39:17 -02:00",
    "contact": { "email": "darlamoore@genmom.com", "phone": "(960) 567-2864" },
    "knownresidences": [
      "888 Celeste Court, Colton, Tennessee, 80627",
      "383 Hicks Street, Barronett, Virgin Islands, 50963",
      "876 Erasmus Street, Vicksburg, Alaska, 60810"
    ]
  }
```

### 2. Create Debezium MongoDB 🍃 connector using the 🔒 `CipherField` SMT for encryption 🔒

The following commands creates a Debezium MongoDB source connector instance. Debezium's MongoDB source connector is configured together with the `CipherField` SMT to perform log-based change data capture against the MongoDB collection `demodb.fake_citizens`. Several fields in the CDC payloads get encrypted based on to the SMT configuration settings.

🧸 [kcctl](https://github.com/kcctl/kcctl) - a CLI for Apache Kafka Connect - is used to perform any Kafka Connect related operations. First the connect cluster address is set and used as the CLI tool's context. Then the MongoDB source connector is created.

```
docker run -it --rm \
    --network sample-scenario \
    -v ${PWD}/data/connect/:/home \
    debezium/tooling:1.2 \
    bash -c "kcctl config set-context default --cluster=http://connect:8083 && kcctl apply -f /home/register_mongodb_source_k4k_enc.json"
```

### 3. 🔎 Inspect the records produced to the Kafka topic

Running the following command shows the resulting kafka records in the corresponding topic:

```
docker run --tty --rm \
    --network sample-scenario \
    debezium/tooling:1.2 \
    kafkacat -b kafka:9092 -C -t mongodb.demodb.fake_citizens -o beginning -q | jq .
```

One such sample Kafka record looks as follows:

```json
 {
  "_id": "6326f8ae2abf405005800a64",
  "personal": {
    "firstname": "Cohen",
    "lastname": "KQE7msoB4V1YUqNJ9RIcgaghzdoF5v0x4srV8JVD3uUB5ZN9laJf58kMMLJrZXnBa7E=",
    "age": "JAE7msoBduIDjgs77ngR8MHMEaiUj2uN+xKiIQ+E3z6Xg3MWDDCya2V5wWux",
    "eyecolor": "KAE7msoBihhRsFt/cJ43D/6gg5emkVIxU25Oh3dHtbHNGYCP7oDLNQwwsmtlecFrsQ==",
    "gender": "male",
    "height": "JQE7msoBmRoWNjVqbLZKR1nXv8WplADRWrhbQiHOZ42fhlbLxAwwsmtlecFrsQ==",
    "weight": "JQE7msoBToMfgPFToD45bFqNQZKJaEm1HIIIq1/k2/nS4ODnrQwwsmtlecFrsQ=="
  },
  "isactive": true,
  "registered": "2021-04-03T08:53:12 -02:00",
  "contact": "mwEBO5rKATXVG0dEE8lZZTUVWQLwtaNgk1Dd1icGiB41jilIE0hXBJO/3moF8NoPCq2Ip+z24qbFKr+V3TABPS/AfRQSEm1RZlaM89O+cS6wcMpCGKkdhch6V3asX3vw6NGqFbIyR1mvIFEpG9lTbrkKAqU7PvEFEP5aCIUzaUO5CKGaMPHEV7E4qCDszqIP84GPwI5prD0sJX40DDCya2V5wWux",
  "knownresidences": [
    "TQE7msoBz9WjqzqCFPHujJrnDiArQRw/6NWyCWf8Iq0Mgu0Ltgs9UWmsJOI3xFeTjxAitSgT3iIZuupR9kHxazXUDsTsUWGEGQUWPZQMMLJrZXnBa7E="
  ]
}
```

Hit `CRTL+C` to stop the consumer process and exit the container.

### 4. Apply 🔒 encrypt/decrypt 🔓 `UDFs` within ksqlDB 🚀 stream processing apps

To enter an interactive ksqldb CLI session run the following command

```
docker compose exec ksqldb-cli ksql http://ksqldb-server:8088
```

Within this CLI session run the ksql statements below:

```sql
SET 'auto.offset.reset'='earliest';

-- create base stream from raw data i.e. partially encrypted
-- Debezium CDC records originating from a MongoDB collection
CREATE STREAM s_fake_citizens(
    _ID VARCHAR,
    PERSONAL STRUCT<FIRSTNAME VARCHAR, LASTNAME VARCHAR, AGE VARCHAR, EYECOLOR VARCHAR, GENDER VARCHAR, HEIGHT VARCHAR, WEIGHT VARCHAR>,
    ISACTIVE BOOLEAN,
    REGISTERED VARCHAR,
    CONTACT VARCHAR,
    KNOWNRESIDENCES ARRAY<VARCHAR>
) WITH (kafka_topic='mongodb.demodb.fake_citizens',value_format='JSON',partitions=1,replicas=1);

-- Create a derived stream which itself contains 
-- sensitive data that must be encrypted before 
-- having it written into backing kafka topic.
CREATE STREAM s_fake_citizens_modified_enc AS 
SELECT 
    K4KENCRYPT(
        CONCAT(
            PERSONAL->FIRSTNAME,' ',K4KDECRYPT(PERSONAL->LASTNAME,'')
        )
    ) AS FULLNAME,
    CASE 
        WHEN CAST(K4KDECRYPT(PERSONAL->WEIGHT,0) AS double) / 
            (K4KDECRYPT(PERSONAL->HEIGHT,0) * K4KDECRYPT(PERSONAL->HEIGHT,0) / 10000.0)
                < 18.5 THEN 'underweight'
        WHEN CAST(K4KDECRYPT(PERSONAL->WEIGHT,0) AS double) / 
            (K4KDECRYPT(PERSONAL->HEIGHT,0) * K4KDECRYPT(PERSONAL->HEIGHT,0) / 10000.0)
                >= 25.0 THEN 'overweight'
        ELSE 'normal weight'
    END AS BMI_CATEGORY,
    K4KDECRYPT(PERSONAL->AGE,0) AS AGE,
    K4KENCRYPT(
        K4KDECRYPT(CONTACT,STRUCT(`email`:='',`phone`:=''))->`phone`
    ) AS PHONE,
    K4KENCRYPT(
        TRANSFORM(KNOWNRESIDENCES,e => REPLACE(K4KDECRYPT(e,''),',',' |'))
        ,array['']
    ) AS ADDRESSES
FROM s_fake_citizens
EMIT CHANGES;
```

The main outcome of this is a new stream called `s_fake_citizens_modified_enc` which is backed by a corresponding Kafka topic. This topic contains derived data which is also partially encrypted and results from the streaming query in the ksql snippet above.

Type `exit` to quit the ksqlDB CLI and exit the container.

### 5. 🔎 Inspect the partially encrypted records in the underlying Kafka topic

Run the following command to show the partially encrypted records in the Kafka topic:

```
docker run --tty --rm \
    --network sample-scenario \
    debezium/tooling:1.2 \
    kafkacat -b kafka:9092 -C -t S_FAKE_CITIZENS_MODIFIED_ENC -o beginning -q | jq .
```

One such sample records looks like the following:

```json
{
  "FULLNAME": "LwE7msoBP5mb3oYl1CSwwEgELLbeFHzcH+185BrYr5LlM1QZPD6Lnw5cclJf8CAMMLJrZXnBa7E=",
  "BMI_CATEGORY": "underweight",
  "AGE": 62,
  "PHONE": "MQE7msoBIo/DCMiE43MU8JLuUOQsAi4GvvLkdc543aJgwzMQccfWeO1PD+KXYs1zAQwwsmtlecFrsQ==",
  "ADDRESSES": [
    "UAE7msoBbKsA18BTvHlgPBGsOTkswNQEJApj8FufKJXw133EIQXYVKaeqrlyMzPUtqkFUWqFH/uPas0YtnTflrHzTxOtUP5IJiHdcG7OvboMMLJrZXnBa7E="
  ]
}
```

Hit `CRTL+C` to stop the consumer process and exit the container.


### 6. Create Camel 🐪 minio (s3) 🪣 connector using the 🔓 `CipherField` SMT for decryption 🔓 

The following creates a Camel MinIO sink connector instance. The Camel MinIO sink connector is configured together with the `CipherField` SMT to decrypt the configured fields from the Kafka records that have been produced by the stream processing job based on the ksqlDB query (see step 4 above)

🧸 [kcctl](https://github.com/kcctl/kcctl) - a CLI for Apache Kafka Connect - is used to perform any Kafka Connect related operations. First the connect cluster address is set and used as the CLI tool's context. Then the MinIO sink connector is created.

```
docker run -it --rm \
    --network sample-scenario \
    -v ${PWD}/data/connect/:/home \
    debezium/tooling:1.2 \
    bash -c "kcctl config set-context default --cluster=http://connect:8083 && kcctl apply -f /home/register_minio_sink_k4k_dec.json"
```

### 7. 🔎 Inspect the decrypted JSON files written into the MinIO bucket 🪣 

Either run `open http://localhost:9001` or directly open this URL in your browser of choice to access MinIO's webUI. Use `admin` (user) and `minio12345` (password) for accessing the page. Browse into the `k4k-decrypt` bucket to inspect the JSON files. One such file which contains the successfully decrypted JSON object looks as follows:

```json
{
    "PHONE": "(897) 455-2185",
    "BMI_CATEGORY": "normal weight",
    "ADDRESSES": [
        "422 Channel Avenue | Biddle | Alabama | 41587",
        "456 Centre Street | Alleghenyville | Georgia | 49431"
    ],
    "FULLNAME": "Vickie Garrett",
    "AGE": 26
}
```

### Bonus: Kryptonite HTTP API

* **cURL decryption example with SMT encrypted data**

```
docker run -it --rm \
    --network sample-scenario \
    debezium/tooling:1.2 bash
    
kafkacat -b kafka:9092 -C -t mongodb.demodb.fake_citizens -o beginning -q -e | jq '{"data": .}' | jq -c '. += {"fieldConfig": [ { "name": "personal", "fieldMode": "ELEMENT" }, { "name": "personal.lastname" }, { "name": "personal.age" }, { "name": "personal.eyecolor" }, { "name": "personal.height" }, { "name": "personal.weight" }, { "name": "contact", "fieldMode": "OBJECT" }, { "name": "knownresidences", "fieldMode": "ELEMENT" } ]}' > connect-smt-2-http-api.json

while read json
do
  curl -s POST 'funqy-http-kryptonite:8080/decrypt-value-with-config' --header 'Content-Type: application/json' --data-raw "$json" | jq .
done < connect-smt-2-http-api.json
```

* **cURL decryption example with UDF encrypted data**

```
docker run -it --rm \
    --network sample-scenario \
    debezium/tooling:1.2 bash

kafkacat -b kafka:9092 -C -t S_FAKE_CITIZENS_MODIFIED_ENC -o beginning -q -e | jq '{"data": .}' | jq -c '. += { "fieldConfig": [ { "name": "FULLNAME" }, { "name": "PHONE" }, { "name": "ADDRESSES", "fieldMode":"ELEMENT" } ]}' > ksqldb-udf-2-http-api.json

while read json
do
  curl -s POST 'funqy-http-kryptonite:8080/decrypt-value-with-config' --header 'Content-Type: application/json' --data-raw "$json" | jq .
done < ksqldb-udf-2-http-api.json
```

* **Python Consumer Scenario with SMT / UDF encrypted data**

```
docker run  -e bootstrap_servers=kafka:9092 -e kryptonite_cipher_mode=decrypt -e kryptonite_kafka_topic=mongodb.demodb.fake_citizens -e kryptonite_field_config='[ { "name": "personal", "fieldMode": "ELEMENT" }, { "name": "personal.lastname" }, { "name": "personal.age" }, { "name": "personal.eyecolor" }, { "name": "personal.height" }, { "name": "personal.weight" }, { "name": "contact", "fieldMode": "OBJECT" }, { "name": "knownresidences", "fieldMode": "ELEMENT" } ]' -it --rm --network=sample-scenario python-demo/kryptonite-http-api:0.1.0

docker run  -e bootstrap_servers=kafka:9092 -e kryptonite_cipher_mode=decrypt -e kryptonite_kafka_topic=S_FAKE_CITIZENS_MODIFIED_ENC -e kryptonite_field_config='[ { "name": "FULLNAME" }, { "name": "PHONE" }, { "name": "ADDRESSES", "fieldMode":"ELEMENT" } ]' -it --rm --network=sample-scenario python-demo/kryptonite-http-api:0.1.0
```

### 8. Stop docker compose environment

Running `docker compose down` stops all services.
