# SurveyPoints-validator
Chequea que la posición del elemento sea la misma de la etiqueta en los puntos geodésicos.

Este mecanismo es un script en Bash que se puede correr en cualquier máquina
Linux.
Usa overpass para descargar los puntos geodésicos de OSM.
Si encuentra diferencias entre la posición y las etiquetas envía un reporte a
algunas personas por medio de correo electrónico.

## Instalación en Ubuntu

```
sudo apt -y install mutt
```

Y seguir algún tutorial de cómo configurarlo:

* https://www.makeuseof.com/install-configure-mutt-with-gmail-on-linux/
* https://www.dagorret.com.ar/como-utilizar-mutt-con-gmail/

Para esto hay que generar un password desde Gmail.


##  Programación desde cron

Solo toca correrlo y validará los puntos de Colombia.

```
# Corre el verificador de ciclovias todos los dias en Bogotá.
0 2 * * * cd ~/SurveyPoints-validator ; ./check.sh
```

## Configuración de destinatarios para envío de reporte.

El reporte generado que ha detectado las diferencias, se puede enviar a
múltiples buzones.
Para esto es necesario establecer la variable de entorno justo antes
de la ejecución:

    export EMAILS="mail1@yahoo.com,mail2@gmail.com"


