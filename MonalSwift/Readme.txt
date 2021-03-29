While monal is almost entirely in Obj-C. There are new methods in swift libraries that are useful.
There is a bug in xcode that casues the bridge header to fail to create to allow swift code to be used in ObjC
if there are mutiple targets. The work around I ahve found  to make a project with a single target that is imported into
the main project.  This is the only reason this poject exists.
