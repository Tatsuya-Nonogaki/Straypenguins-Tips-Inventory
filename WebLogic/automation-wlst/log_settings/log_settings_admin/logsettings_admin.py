#!/usr/bin/python
import time
import getopt
import sys
import re

def print_value(holder):
    val=get(holder)
    print holder, '=', val

# Get location of the properties file.
listonly=0
properties = ''
try:
   opts, args = getopt.getopt(sys.argv[1:],"p:lh",["properies="])
except getopt.GetoptError:
   print 'logsettings.py -p <path-to-properties-file>'
   sys.exit(2)
for opt, arg in opts:
   if opt == '-h':
      print 'logsettings.py -p <path-to-properties-file>'
      sys.exit()
   elif opt == '-l':
      listonly = 1
   elif opt in ("-p", "--properties"):
      properties = arg
print 'properties=', properties

# Load the properties from the properties file.
from java.io import FileInputStream
 
propInputStream = FileInputStream(properties)
configProps = Properties()
configProps.load(propInputStream)

# Set all variables from values in properties file.
adminUsername=configProps.get("admin.username")
adminPassword=configProps.get("admin.password")
adminURL=configProps.get("admin.url")
# Details
svName=configProps.get("sv.name")
rotationType=configProps.get("log.rotation.type")
rotationCount=configProps.get("log.rotation.count")

# Display the variable values.
print 'adminUsername=', adminUsername
print 'adminPassword= ****'
print 'adminURL=', adminURL
# Details
print 'svName=', svName
print 'rotationType=', rotationType
print 'rotationCount=', rotationCount

# Connect to the AdminServer.
connect(adminUsername, adminPassword, adminURL)

if not listonly:
    edit()
    startEdit()

# Manage common server logging.
cd('/Servers/' + svName + '/Log/' + svName)
if not listonly:
    cmo.setRotationType(rotationType)
    cmo.setFileCount(int(rotationCount))
    #cmo.setRedirectStderrToServerLogEnabled(true)
    #cmo.setRedirectStdoutToServerLogEnabled(true)
    #cmo.setMemoryBufferSeverity('Debug')
    #cmo.setLogFileSeverity('Notice')

print '\n---- Result: common server logging'
print_value('RotationType')
print_value('FileCount')

# Manage WebServer logging.
cd('/Servers/' + svName + '/WebServer/' + svName + '/WebServerLog/' + svName)
if not listonly:
    cmo.setRotationType(rotationType)
    cmo.setFileCount(int(rotationCount))

print '\n---- Result: WebServer logging'
print_value('RotationType')
print_value('FileCount')
print_value('LogFileFormat')
print_value('ELFFields')
print ""

if not listonly:
    save()
    activate()

disconnect()
exit()
