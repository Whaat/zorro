require 'sketchup.rb'
require 'extensions.rb'

module DM

module Zorro

  VERSION = "2.0.0"
  PLUGIN_NAME = "Zorro 2".freeze
  PLUGIN = self

  ext = SketchupExtension.new(PLUGIN_NAME, (File.join(File.dirname(__FILE__),"DM_zorro", "zorro")))
  ext.description = ("Slice objects in your model or slice a model from a section cut.")
  ext.version = VERSION
  ext.creator = "Dale Martens (Whaat)"
  ext.copyright = "2016, MindSight Studios Inc. All rights reserved."
  Sketchup.register_extension ext, true
end

end