<?xml version="1.0" encoding="UTF-8"?>
<tileset version="1.10" tiledversion="1.11.2" name="collision" tilewidth="8" tileheight="8" tilecount="8" columns="4">
 <properties>
  <property name="Blocked" type="bool" value="true"/>
 </properties>
 <image source="sprites/collisino.png" width="32" height="16"/>
 <tile id="0">
  <properties>
   <property name="blocked" type="bool" value="true"/>
  </properties>
 </tile>
 <tile id="1">
  <properties>
   <property name="jump" value="down"/>
  </properties>
 </tile>
 <tile id="2">
  <properties>
   <property name="water" type="bool" value="true"/>
  </properties>
 </tile>
 <tile id="4">
  <properties>
   <property name="jump" value="right"/>
  </properties>
 </tile>
 <tile id="5">
  <properties>
   <property name="jump" value="left"/>
  </properties>
 </tile>
 <tile id="6">
  <properties>
   <property name="grass" type="bool" value="true"/>
  </properties>
 </tile>
</tileset>
