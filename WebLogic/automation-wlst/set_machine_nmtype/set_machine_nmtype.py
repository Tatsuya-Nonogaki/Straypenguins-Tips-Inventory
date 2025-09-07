#!/usr/bin/python
import time
import getopt
import sys
import re

def print_help():
   print 'set_machine_nmtype.py -p <path-to-properties-file> -m <machine-name> -t <nmtype>'
   print '*nmtype is usually "SSL" or "Plain".'

def print_value(holder):
   val=get(holder)
   print holder, '=', val

# Get setting specification.
listonly=0
properties = ''
machinename = ''
nmtype = ''
try:
   opts, args = getopt.getopt(sys.argv[1:],"p:m:t:lh",["properies=","machinename=","type="])
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
   elif opt in ("-m", "--machinename"):
      machinename = arg
   elif opt in ("-t", "--type"):
      nmtype = arg
print 'properties =', properties
print 'machinename =', machinename
print 'nmtype =', nmtype

if not machinename:
   print_help()
   sys.exit(2)
elif (nmtype=='' and not listonly):
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

# Manage machine nodemanager type.
cd('/Machines/' + machinename + '/NodeManager/' + machinename)
if not listonly:
    cmo.setNMType(nmtype)

print '---- Result:'
print_value('NMType')
print ""

if not listonly:
    save()
    activate()

disconnect()
exit()
