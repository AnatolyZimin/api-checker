/***
 *   Copyright 2014 Rackspace US, Inc.
 *
 *   Licensed under the Apache License, Version 2.0 (the "License");
 *   you may not use this file except in compliance with the License.
 *   You may obtain a copy of the License at
 *
 *       http://www.apache.org/licenses/LICENSE-2.0
 *
 *   Unless required by applicable law or agreed to in writing, software
 *   distributed under the License is distributed on an "AS IS" BASIS,
 *   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 *   See the License for the specific language governing permissions and
 *   limitations under the License.
 */
package com.rackspace.com.papi.components.checker.handler

import java.lang.management._
import java.net.URLDecoder
import java.util.{Collections, LinkedHashMap}
import java.util.concurrent.atomic.AtomicLong
import javax.management._
import javax.servlet.FilterChain

import com.rackspace.com.papi.components.checker.Validator
import com.rackspace.com.papi.components.checker.servlet._
import com.rackspace.com.papi.components.checker.step.results.{MismatchResult, MultiFailResult, Result}
import com.yammer.metrics.scala.{Instrumented, Meter}
import org.w3c.dom.{Document, Element}

class InstrumentedHandler extends ResultHandler with Instrumented with InstrumentedHandlerMBean {

  private val platformMBeanServer = ManagementFactory.getPlatformMBeanServer()
  private var latestFailMBeanName : Option[ObjectName] = None

  private var validator : Option[Validator] = None

  private case class FailData(val reqValue : String, val result : Result, val count : AtomicLong) {}

  private class FailMap[K,V](private val _capacity : Int)  extends LinkedHashMap[K,V](_capacity+1, 1.1.asInstanceOf[Float], true) {
    override protected def removeEldestEntry(entry : java.util.Map.Entry[K,V]) = size() > _capacity;
  }

  private var stepMeters : Map[String, Meter] = Map.empty
  private val lastFailedCapacity : Int = Integer.getInteger("com.rackspace.com.papi.components.checker.handler.InstrumentedHandler.LastFailedCapacity", 25)
  private val lastFailed = Collections.synchronizedMap(new FailMap[Result,FailData](lastFailedCapacity))

  override def init (validator : Validator, checker : Option[Document]) : Unit = {

    this.validator = Some(validator)

    if (checker != None) {
      val elms = checker.get.getElementsByTagNameNS("http://www.rackspace.com/repose/wadl/checker",
                                                    "step")
      for (i <- 0 to (elms.getLength-1)) {
        val elm = elms.item(i).asInstanceOf[Element]

        val id = elm.getAttribute("id")
        val etype = elm.getAttribute("type")

        stepMeters = stepMeters + (id -> metrics.meter(id, etype, validator.name))
      }
    }

    //
    // Register the MBean
    //
    latestFailMBeanName = Some(new ObjectName("\"com.rackspace.com.papi.components.checker.handler\":type=\"InstrumentedHandler\",scope=\""+
                                   validator.name+"\",name=\"latestFails\""))
    platformMBeanServer.registerMBean(this,latestFailMBeanName.get)
  }

  private def markResult (result : Result) : Unit = {
    result match {
      case m : MultiFailResult => m.stepIDs.foreach(s => stepMeters(s).mark)
                                  m.fails.foreach (f => markResult(f))
      case mr : MismatchResult => ; /* Ignore these, since it's a mismatch */
      case r : Result => r.stepIDs.foreach (s => stepMeters(s).mark)
    }
  }

  private def markFail (result : Result, req : CheckerServletRequest) : Unit = {
    val fail = {
      val last = lastFailed.get(result)
      last match {
        case null => val n = FailData(req.getMethod()+" "+URLDecoder.decode(req.getRequestURI(), "UTF-8"), result, new AtomicLong())
                     lastFailed.put(result, n)
                     n
        case _  => last
      }
    }
    fail.count.incrementAndGet()
  }

  override def handle (req : CheckerServletRequest, resp : CheckerServletResponse, chain : FilterChain, result : Result)  : Unit = {
    markResult(result)
    if (!result.valid) {
      markFail(result, req)
    }
  }

  override def getLatestFails : Array[String] = {
    val data : Array[FailData] = lastFailed.values().toArray(new Array[FailData](0))
    for { d <- data } yield d.toString
  }

  override def destroy : Unit = {
    if (latestFailMBeanName != None) {
      platformMBeanServer.unregisterMBean(latestFailMBeanName.get)
      latestFailMBeanName = None
    }

    if (validator != None) {
      stepMeters.keys.foreach ( k => metricsRegistry.removeMetric(getClass, k, validator.get.name))
      validator = None
      stepMeters = Map.empty
    }
  }
}
