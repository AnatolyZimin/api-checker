<?xml version="1.0" encoding="UTF-8"?>
<!--
   removeDups.xsl

   This stylesheet takes a document in checker format and removes
   duplicate states. The stylesheet considers a state a duplicate if
   it matches on the same kind of input AND it attaches to the same
   states on output. It then replaces those states with a single
   state.

   For example:

              +===+
             /+ B +=
   +===+ /=== +===+ \    +===+
   | A +=            +===+ C |
   +===+ \=== +===+ /    +===+
             \+ B +=
              +===+

    Becomes:

    +===+    +===+     +===+
    | A +====+ B +=====+ C |
    +===+    +===+     +===+

   The process operates in a recursive manner until all duplicates are
   replaced.

   Copyright 2014 Rackspace US, Inc.

   Licensed under the Apache License, Version 2.0 (the "License");
   you may not use this file except in compliance with the License.
   You may obtain a copy of the License at

       http://www.apache.org/licenses/LICENSE-2.0

   Unless required by applicable law or agreed to in writing, software
   distributed under the License is distributed on an "AS IS" BASIS,
   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
   See the License for the specific language governing permissions and
   limitations under the License.
-->
<xsl:stylesheet
    xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
    xmlns:xsd="http://www.w3.org/2001/XMLSchema"
    xmlns:check="http://www.rackspace.com/repose/wadl/checker"
    xmlns="http://www.rackspace.com/repose/wadl/checker"
    exclude-result-prefixes="xsd check"
    version="2.0">

    <xsl:import href="../util/funs.xsl"/>
    <xsl:include href="removeDups-rules.xsl"/>

    <xsl:output indent="yes" method="xml"/>

    <xsl:template match="check:checker" name="replaceAllDups">
        <xsl:param name="checker" select="." as="node()"/>
        <xsl:variable name="dups" as="node()">
            <xsl:call-template name="getDups">
                <xsl:with-param name="checker" select="$checker"/>
            </xsl:call-template>
        </xsl:variable>
        <xsl:choose>
            <xsl:when test="not($dups/check:group)">
                <!-- No duplicats found, tidy up empty epsillon cases -->
                <checker>
                  <xsl:copy-of select="/check:checker/namespace::*"/>
                  <xsl:apply-templates select="/check:checker/check:meta" mode="copyMeta"/>
                  <xsl:copy-of select="/check:checker/check:grammar"/>
                  <xsl:apply-templates select="$checker" mode="epsilonRemove"/>
                </checker>
            </xsl:when>
            <xsl:otherwise>
                <xsl:call-template name="replaceAllDups">
                    <xsl:with-param name="checker">
                        <xsl:call-template name="replaceDups">
                            <xsl:with-param name="checker" select="$checker"/>
                            <xsl:with-param name="dups" select="$dups"/>
                        </xsl:call-template>
                    </xsl:with-param>
                </xsl:call-template>
            </xsl:otherwise>
        </xsl:choose>
    </xsl:template>

    <xsl:template match="@* | node()" mode="copyMeta" priority="10">
        <xsl:copy>
            <xsl:apply-templates select="@* | node()" mode="copyMeta"/>
        </xsl:copy>
    </xsl:template>

    <xsl:template match="check:checker" name="replaceEpsilons" mode="epsilonRemove">
        <xsl:param name="checker" select="." as="node()"/>
        <xsl:variable name="dups" as="node()">
            <xsl:call-template name="getEpsilonDups">
                <xsl:with-param name="checker" select="$checker"/>
            </xsl:call-template>
        </xsl:variable>
        <xsl:choose>
            <xsl:when test="not($dups/check:group)">
                <xsl:for-each select="$checker//check:step">
                    <xsl:copy-of select="."/>
                </xsl:for-each>
            </xsl:when>
            <xsl:otherwise>
                <xsl:call-template name="replaceEpsilons">
                    <xsl:with-param name="checker">
                        <xsl:call-template name="replaceDups">
                            <xsl:with-param name="checker" select="$checker"/>
                            <xsl:with-param name="dups" select="$dups"/>
                        </xsl:call-template>
                    </xsl:with-param>
                </xsl:call-template>
            </xsl:otherwise>
        </xsl:choose>
    </xsl:template>

    <xsl:template name="replaceDups">
        <xsl:param name="checker" as="node()"/>
        <xsl:param name="dups" as="node()"/>
        <xsl:variable name="excludes" as="xsd:string*">
            <xsl:sequence select="tokenize(string-join($dups/check:group/@exclude,' '),' ')"/>
        </xsl:variable>
        <checker>
            <xsl:apply-templates select="$checker" mode="unDup">
                <xsl:with-param name="dups" select="$dups"/>
                <xsl:with-param name="excludes" select="$excludes"/>
            </xsl:apply-templates>
        </checker>
    </xsl:template>

    <xsl:template match="check:step" mode="unDup">
        <xsl:param name="dups" as="node()"/>
        <xsl:param name="excludes" as="xsd:string*"/>
        <xsl:choose>
            <xsl:when test="$excludes = @id"/>
            <xsl:otherwise>
                <step>
                    <xsl:apply-templates select="@*" mode="unDup">
                        <xsl:with-param name="dups" select="$dups"/>
                        <xsl:with-param name="excludes" select="$excludes"/>
                        <xsl:with-param name="id" select="@id"/>
                    </xsl:apply-templates>
                    <xsl:copy-of select="element()"/>
                </step>
            </xsl:otherwise>
        </xsl:choose>
    </xsl:template>

    <xsl:template match="@*" mode="unDup">
        <xsl:param name="dups" as="node()"/>
        <xsl:param name="excludes" as="xsd:string*"/>
        <xsl:param name="id" as="xsd:string"/>
        <xsl:choose>
            <!-- Substitude excludes from nexts -->
            <xsl:when test="name() = 'next'">
                <xsl:variable name="nexts" as="xsd:string*" select="tokenize(.,' ')"/>
                <xsl:attribute name="next">
                  <xsl:value-of select="check:removeDupNext(check:swapExclude($nexts,$excludes,$dups))" separator=" "/>
                </xsl:attribute>
            </xsl:when>
            <!-- Copy labels only if all excluded labels match -->
            <xsl:when test="name() = 'label'">
                <xsl:variable name="excludedIDs" as="xsd:string*" select="tokenize($dups/check:group[@include=$id]/@exclude, ' ')"/>
                <xsl:variable name="excludedLabels" select="//check:step[@id=$excludedIDs]/@label" as="xsd:string*"/>
                <xsl:if test="every $l in $excludedLabels satisfies $l=.">
                    <xsl:copy/>
                </xsl:if>
            </xsl:when>
            <xsl:otherwise>
                <xsl:copy/>
            </xsl:otherwise>
        </xsl:choose>
    </xsl:template>

    <xsl:function name="check:removeDupNext" as="xsd:string*">
        <xsl:param name="nexts" as="xsd:string*"/>
        <xsl:for-each-group select="$nexts" group-by=".">
            <xsl:value-of select="current-group()[1]"/>
        </xsl:for-each-group>
    </xsl:function>

    <xsl:function name="check:swapExclude" as="xsd:string*">
        <xsl:param name="nexts" as="xsd:string*"/>
        <xsl:param name="excludes" as="xsd:string*"/>
        <xsl:param name="dups" as="node()"/>
        <xsl:sequence select="for $n in $nexts return if ($excludes = $n) then
                              $dups/check:group/@include[tokenize(../@exclude,' ') = $n]
                              else $n"/>
    </xsl:function>

    <xsl:template name="getEpsilonDups" as="node()">
        <xsl:param name="checker" as="node()"/>
        <checker>
            <!-- Treat epsilon methods as dups -->
            <xsl:for-each select="$checker//check:step[@type='METHOD']">
                <xsl:variable name="nexts" as="xsd:string*" select="tokenize(@next,' ')"/>
                <xsl:variable name="nextStep" as="node()*" select="$checker//check:step[@id = $nexts]"/>
                <xsl:if test="every $s in $nextStep satisfies $s/@type='METHOD'">
                    <group>
                        <xsl:attribute name="include" select="$nexts" separator=" "/>
                        <xsl:attribute name="exclude" select="@id"/>
                    </group>
                </xsl:if>
            </xsl:for-each>
        </checker>
    </xsl:template>


    <xsl:template match="text()" mode="#all"/>
</xsl:stylesheet>
