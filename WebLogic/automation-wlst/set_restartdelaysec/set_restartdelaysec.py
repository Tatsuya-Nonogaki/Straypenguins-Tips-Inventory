#!/usr/bin/python
import time
import getopt
import sys
import re

def print_help():
   print 'set_restartdelaysec.py -p <path-to-properties-file> -s <server-name> -v <sec>'

def print_value(holder):
   val=get(holder)
   print holder, '=', val

# Get setting specification.
listonly=0
properties = ''
svName = ''
sec = ''
try:
   opts, args = getopt.getopt(sys.argv[1:],"p:s:v:lh",["properies=","svname=","sec="])
except getopt.GetoptError:
   print_help()
   sys.exit(2)
for opt, arg in opts:
   if opt == '-h':
      print_help()
      sys.exit()
   elif opt == '-l':
      listonly = 1
   elif opt in ("-p", "--properties"):
      properties = arg
   elif opt in ("-s", "--svname"):
      svName = arg
   elif opt in ("-v", "--sec"):
      sec = arg
print 'properties =', properties
print 'svName =', svName
print 'sec =', sec

if not svName:
   print_help()
   sys.exit(2)
elif (sec=='' and not listonly):
   print_help()
   sys.exit(2)

# Load the properties from the properties file.
from java.io import FileInputStream
 
propInputStream = FileInputStream(properties)
configProps = Properties()
configProps.load(propInputStream)

# Set all variables from values in properties file.
adminUsername=configProps.get("admin.username")
adminPassword=configProps.get("admin.password")
adminURL=configProps.get("admin.url")

# Display the variable values.
print 'adminUsername=', adminUsername
print 'adminPassword= ****'
print 'adminURL=', adminURL

# Connect to the AdminServer.
connect(adminUsername, adminPassword, adminURL)

if not listonly:
    edit()
    startEdit()

# Manage the setting.
cd('/Servers/' + svName)
if not listonly:
    cmo.setRestartDelaySeconds(sec)

print '---- Result:'
print_value('RestartDelaySeconds')
print ""

if not listonly:
    save()
    activate()

disconnect()
exit()
