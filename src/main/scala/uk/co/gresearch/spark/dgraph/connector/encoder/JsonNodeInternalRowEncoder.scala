/*
 * Copyright 2020 G-Research
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

package uk.co.gresearch.spark.dgraph.connector.encoder

import java.sql.Timestamp
import java.time.ZonedDateTime
import java.time.format.DateTimeFormatter

import com.google.gson.{Gson, JsonArray, JsonElement, JsonObject}
import org.apache.spark.sql.catalyst.InternalRow
import org.apache.spark.sql.types.StructType
import uk.co.gresearch.spark.dgraph.connector.{Geo, Json, Logging, Password, Uid}

import scala.collection.JavaConverters._

/**
 * Helper methods to turn Dgraph json results into JsonObjects representing Dgraph nodes.
 */
trait JsonNodeInternalRowEncoder extends InternalRowEncoder with Logging {

  /**
   * Sets the schema of this encoder. This encoder may only partially or not at all use the given schema.
   * Default implementation ignores the given schema completely.
   * @param schema a schema
   * @return encoder with the given schema
   */
  override def withSchema(schema: StructType): JsonNodeInternalRowEncoder = this

  /**
   * Encodes the given Dgraph json result into InternalRows.
   *
   * @param json Json result
   * @param member member in the json that has the result
   * @return internal rows
   */
  def fromJson(json: Json, member: String): Iterator[InternalRow] =
    fromJson(getResult(json, member))

  /**
   * Encodes the given Dgraph json result into InternalRows.
   *
   * @param result Json result
   * @return internal rows
   */
  def fromJson(result: JsonArray): Iterator[InternalRow]

  /**
   * Parses the given Json result and returns the result array.
   * @param json Json result
   * @param member member in the json that has the result
   * @return Json array
   */
  def getResult(json: Json, member: String): JsonArray = {
    try {
      new Gson().fromJson(json.string, classOf[JsonObject]).getAsJsonArray(member)
    } catch {
      case t: Throwable =>
        log.error(s"failed to parse element '$member' in dgraph json result: ${abbreviate(json.string)}")
        throw t
    }
  }

  /**
   * Provides the result elements as JsonObjects
   * @param result Json array
   * @return result elements
   */
  def getNodes(result: JsonArray): Iterator[JsonObject] =
    result
      .iterator()
      .asScala
      .map(_.getAsJsonObject)

  def getValues(value: JsonElement): Iterable[JsonElement] = value match {
    case a: JsonArray => a.asScala
    case _ => Seq(value)
  }

  /**
   * Get the value of the given JsonElement in the given type. The value can be a JsonPrimitive
   * representing property values or a JsonObject representing an edge destination node.
   *
   * Types are interpreted as Dgraph types (where int is Long), for non-Dgraph types recognizes
   * as respective Spark / Scala types.
   *
   * @param value JsonElement
   * @param valueType type as string
   * @return typed value
   */
  def getValue(value: JsonElement, valueType: String): Any =
    valueType match {
      // the uid of a node, the subject of a triple
      case "subject" => Uid(value.getAsString)
      // https://dgraph.io/docs/dql/predicate-types/#scalar-types
      case "uid" => Uid(value.getAsJsonObject.get("uid").getAsString)
      case "string" => value.getAsString
      case "int" | "long" => value.getAsLong
      case "float" | "double" => value.getAsDouble
      case "datetime" | "timestamp" =>
        Timestamp.valueOf(ZonedDateTime.parse(value.getAsString, DateTimeFormatter.ISO_OFFSET_DATE_TIME).toLocalDateTime)
      case "bool" | "boolean" => value.getAsString == "true"
      case "geo" => Geo(value.getAsJsonObject.toString)
      case "password" => Password(value.getAsJsonObject.getAsString)
      case "default" => value.getAsString
      case _ => value.getAsString
    }

  /**
   * Get the type of the given value as a string. Only supports Dgraph types (no Integer or Float),
   * returns Spark / Scala type string, not Dgraph (where int refers to Long).
   * @param value value
   * @return value's type
   */
  def getType(value: Any): String =
    value match {
      case _: Uid => "uid"
      case _: String => "string"
      case _: Long => "long"
      case _: Double => "double"
      case _: java.sql.Timestamp => "timestamp"
      case _: Boolean => "boolean"
      case _: Geo => "geo"
      case _: Password => "password"
      case _ => "default"
    }

}
