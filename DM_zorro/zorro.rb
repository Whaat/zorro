#Zorro version 2.0 - created by Dale Martens (Whaat)
#Code used from TIG's script Section CutFace to get section cutting plane
require 'sketchup.rb'

module DM::Zorro

  class Zorro2Tool

    def initialize
      @ip1 = nil
      @ip2 = nil
      @xdown = 0
      @ydown = 0
      @x1=0
      @x2=0
      @y1=0
      @y2=0
      @helper_group=nil
      @cursor = UI.create_cursor(File.join(File.dirname(__FILE__), 'images', 'sword.png'), 1, 1)
    end

    def activate
      @ip1 = Sketchup::InputPoint.new
      @ip2 = Sketchup::InputPoint.new
      @ip = Sketchup::InputPoint.new
      @drawn = false
      self.reset(nil)
    end

    def onSetCursor
      UI.set_cursor(@cursor)
    end

    def deactivate(view)
      view.invalidate if @drawn
    end

    def onMouseMove(flags, x, y, view)
      if @state == 0
        @ip.pick view, x, y
        if @ip != @ip1
          view.invalidate if( @ip.display? or @ip1.display? )
          @ip1.copy! @ip
          @x1=x
          @y1=y
          view.tooltip = @ip1.tooltip
        end
      else
        @ip2.pick view, x, y, @ip1
        view.tooltip = @ip2.tooltip if( @ip2.valid? )
        view.invalidate
        if @ip2.valid?
          length = @ip1.position.distance(@ip2.position)
          Sketchup::set_status_text length.to_s, SB_VCB_VALUE
          @x2=x
          @y2=y
        end
        if (x-@xdown).abs > 10 || (y-@ydown).abs > 10
          @dragging = true
        end
      end
    end

    # The onLButtonDOwn method is called when the user presses the left mouse button.
    def onLButtonDown(flags, x, y, view)
      # When the user clicks the first time, we switch to getting the
      # second point.  When they click a second time we create the line
      if @state == 0
        @ip1.pick view, x, y
        if @ip1.valid?
          @state = 1
          Sketchup::set_status_text("Draw cut line through geometry.  Hold CTRL to cut through nested groups and components.", SB_PROMPT)
          @xdown = x
          @ydown = y
          @x1=x
          @y1=y
        end
      else
        # create the line on the second click
        if @ip2.valid?
          self.cut_geometry(view)
          self.reset(view)
        end
      end

      # Clear any inference lock
      view.lock_inference
    end

# The onLButtonUp method is called when the user releases the left mouse button.
    def onLButtonUp(flags, x, y, view)
      # If we are doing a drag, then create the line on the mouse up event
      if @dragging && @ip2.valid?
        self.cut_geometry(view)
        self.reset(view)
      end
    end

    def onKeyDown(key, repeat, flags, view)
      if key == CONSTRAIN_MODIFIER_KEY && repeat == 1
        @shift_down_time = Time.now

        # if we already have an inference lock, then unlock it
        if view.inference_locked?
          # calling lock_inference with no arguments actually unlocks
          view.lock_inference
        elsif @state == 0 && @ip1.valid?
          view.lock_inference @ip1
        elsif @state == 1 && @ip2.valid?
          view.lock_inference @ip2, @ip1
        end
      end
      if key==COPY_MODIFIER_KEY && repeat==1
        @copy_down=true
      end
    end


    def onKeyUp(key, repeat, flags, view)
      if key == CONSTRAIN_MODIFIER_KEY &&
          view.inference_locked? &&
          (Time.now - @shift_down_time) > 0.5
        view.lock_inference
      end
      if key==COPY_MODIFIER_KEY
        @copy_down=false
      end
    end


    def draw(view)
      if @ip1.valid?
        if @ip1.display?
          @ip1.draw(view)
          @drawn = true
        end

        if @ip2.valid?
          @ip2.draw(view) if( @ip2.display? )

          view.set_color_from_line(@ip1, @ip2)
          # self.draw_geometry([@x1,@y1,0],[@x2,@y1,0],[@x2,@y2,0],[@x1,@y2,0], view)
          self.draw_geometry(@ip1.position,@ip2.position,view)
          @drawn = true
        end
      end
    end

    def getExtents
      box=Sketchup.active_model.bounds
      box.add(@ip1.position) if @ip1.valid?
      box.add(@ip.position) if @ip.valid?
      box.add(@ip2.position) if @ip2.valid?
      box
    end

    def onCancel(flag, view)
      self.reset(view)
    end

    # Reset the tool back to its initial state
    def reset(view)
      # This variable keeps track of which point we are currently getting
      @state = 0
      @x1=0
      @x2=0
      @y1=0
      @y2=0

      # Display a prompt on the status bar
      Sketchup::set_status_text(("Draw cut line through geometry.  CTRL=Cut Nested Geometry"), SB_PROMPT)

      # clear the InputPoints
      @ip1.clear
      @ip2.clear

      if view
        view.tooltip = nil
        view.invalidate if @drawn
      end
      @drawn = false
      @dragging = false
    end

    def cut_geometry(view)
      Sketchup.active_model.start_operation("Zorro",true)

      eye=view.camera.eye
      p1=@ip1.position
      p2=@ip2.position
      s1=view.screen_coords(p1)
      s2=view.screen_coords(p2)
      ray1=view.pickray(s1.x,s1.y)
      ray2=view.pickray(s2.x,s2.y)

      sv1=ray1[1]
      sv2=ray2[1]

      box=Sketchup.active_model.bounds
      center=box.center
      diagonal=box.diagonal
      #get the distance from the center of the model to the bounding box
      distance=eye.distance(center)+(2*diagonal)

      if sv1==sv2  #this occurs when camera is orthogonal
        p1=p1.offset(sv1.reverse,distance)
        p2=p2.offset(sv2.reverse,distance)
        p3=p1.offset(sv1,2*distance)
        p4=p2.offset(sv2,2*distance)
      else
        p1 = p1.offset(sv1, 2*distance)
        p2 = p2.offset(sv2, 2*distance)
      end

      ents=Sketchup.active_model.active_entities
      knife_group=ents.add_group
      knife_ents=knife_group.entities
      knife=knife_ents.add_face(eye,p1,p2) if sv1!=sv2
      knife=knife_ents.add_face(p1,p2,p4,p3) if sv1==sv2    #modified knife for orthogonal views

      if @copy_down
        Sketchup.set_status_text("Making unique components...")
        make_unique_zorro_cut(ents,Geom::Transformation.new,knife.plane)
        nested_slash(ents.parent,Geom::Transformation.new,knife_group,knife_group.transformation)
      else
        ents.intersect_with(false,Geom::Transformation.new,ents,Geom::Transformation.new,false,[knife_group])
      end
      ents.erase_entities(knife_group)
      delete_helpers
      Sketchup.active_model.commit_operation
    rescue
      Sketchup.active_model.abort_operation
    end

    def delete_helpers()
      Sketchup.active_model.active_entities.erase_entities(@helper_group) if @helper_group
      @helper_group=nil
    end

    def nested_slash(first,t1,second,t2)
      ents=get_entities(first)
      nested=0
      ents.each {|e|
        if e.visible?
          if e.class==Sketchup::Group or e.class==Sketchup::ComponentInstance
            Sketchup.set_status_text("Cutting #{get_entities(e).parent.name}...")
            nested+=1
            nested_slash(e,t1*e.transformation,second,t2)
          end
        end
      }

      slash(first,t1,second,t2)
    end

    def slash(inst1,t1,inst2,t2)
      if intersects_plane?(inst1,t1,inst2,t2)
        #inst1.make_unique if inst1.class==Sketchup::Group
        #inst1.make_unique if inst1.class==Sketchup::ComponentInstance
        ents1=get_entities(inst1)
        ents2=get_entities(inst2)
        #$new_edges=[] if not $new_edges
        edges=ents1.intersect_with(false,t1,ents1,t1,false,[inst2])
        #$new_edges.push(edges)
        #edges.each {|e| e.find_faces}
      else
        return
      end
    end

    #################inst1 must be a group or component, plane group must contain a single face
    def intersects_plane?(inst1,t1,plane_group,t2)
      #we will perform a test intersection to see if any new edges were created.
      if @helper_group==nil
        @helper_group=Sketchup.active_model.active_entities.add_group  #this group will contain the edges from the test intersection
        @helper_group.entities.add_cpoint([0,0,0])  #adding a construction point to ensure that this group contains something to avoid automatic deletion by SketchUp
      end
      ents1=get_entities(inst1)
      ents2=@helper_group.entities
      new_edges=ents1.intersect_with(false,t1,ents2,@helper_group.transformation,false,[plane_group])

      if new_edges.length>0  #if new edges were created by the intersection
        return true
      else
        return false
      end
    end

    def bounds_intersects_plane?(inst1,t1,plane)
      bounds=inst1.bounds
      bmin  = bounds.min
      bminx = bmin.x
      bminy = bmin.y
      bminz = bmin.z
      bmax  = bounds.max
      bmaxx = bmax.x
      bmaxy = bmax.y
      bmaxz = bmax.z
      pts=[bminx, bminy, bminz],[bmaxx, bminy, bminz],[bminx, bminy, bmaxz],[bmaxx, bminy, bmaxz],[bminx, bmaxy, bmaxz],[bmaxx, bmaxy, bmaxz],[bminx, bmaxy, bminz],[bmaxx, bmaxy, bminz]
      pts=pts.collect {|p| p.transform(t1)}

      behind=nil
      in_front=nil

      behind=pts.find {|p| (plane[0]*p.x+plane[1]*p.y+plane[2]*p.z+plane[3])<0.0}
      in_front=pts.find {|p| (plane[0]*p.x+plane[1]*p.y+plane[2]*p.z+plane[3])>0.0}

      if behind!=nil and in_front!=nil
        if inst1.name!=""
          #p inst1.name
          #p "bounds intersects"
        end
        return 0
      elsif behind!=nil and in_front==nil
        if inst1.name!=""
          #p inst1.name
          #p "behind plane"

        end
        return -1
      elsif behind==nil and in_front!=nil
        if inst1.name!=""
          #p inst1.name
          #p "in front"

        end
        return 1
      end
    end

    # Draw the geometry
    def draw_geometry(pt1, pt2, view)
      screen1=view.screen_coords(pt1)
      screen2=view.screen_coords(pt2)
      view.draw2d(GL_LINES,[screen1,screen2])
      #view.draw_line(pt1,pt2)
    end

    ##creates a cutting face from a section plane  - code used from with permission from TIG's script SectionCutFace
    def create_face_from_section(section)
      plane=section.get_plane
      bounds=Sketchup.active_model.bounds
      entities=Sketchup.active_model.active_entities
      bmin  = bounds.min
      bminx = bmin.x
      bminy = bmin.y
      bminz = bmin.z
      bmax  = bounds.max
      bmaxx = bmax.x
      bmaxy = bmax.y
      bmaxz = bmax.z
      ### make group
      newgroup=entities.add_group
      newgroupentities=newgroup.entities
      c1 = [bminx, bminy, bminz]
      c2 = [bmaxx, bminy, bminz]
      c3 = [bminx, bminy, bmaxz]
      c4 = [bmaxx, bminy, bmaxz]
      c5 = [bminx, bmaxy, bmaxz]
      c6 = [bmaxx, bmaxy, bmaxz]
      c7 = [bminx, bmaxy, bminz]
      c8 = [bmaxx, bmaxy, bminz]
      e1 = newgroupentities.add_edges [ c1, c2 ]
      e2 = newgroupentities.add_edges [ c3, c4 ]
      e3 = newgroupentities.add_edges [ c5, c6 ]
      e4 = newgroupentities.add_edges [ c7, c8 ]
      e5 = newgroupentities.add_edges [ c1, c3 ]
      e6 = newgroupentities.add_edges [ c2, c4 ]
      e7 = newgroupentities.add_edges [ c7, c5 ]
      e8 = newgroupentities.add_edges [ c8, c6 ]
      e9 = newgroupentities.add_edges [ c1, c7 ]
      e10 = newgroupentities.add_edges [ c3, c5 ]
      e11 = newgroupentities.add_edges [ c4, c6 ]
      e12 = newgroupentities.add_edges [ c2, c8 ]
      line1 = e1[0].line
      line2 = e2[0].line
      line3 = e3[0].line
      line4 = e4[0].line
      line5 = e5[0].line
      line6 = e6[0].line
      line7 = e7[0].line
      line8 = e8[0].line
      line9 = e9[0].line
      line10 = e10[0].line
      line11 = e11[0].line
      line12 = e12[0].line
      e1[0].erase!
      e2[0].erase!
      e3[0].erase!
      e4[0].erase!
      e5[0].erase!
      e6[0].erase!
      e7[0].erase!
      e8[0].erase!
      e9[0].erase!
      e10[0].erase!
      e11[0].erase!
      e12[0].erase!
      ### find intersects with plane
      p1 = Geom.intersect_line_plane line1, plane
      p2 = Geom.intersect_line_plane line2, plane
      p3 = Geom.intersect_line_plane line3, plane
      p4 = Geom.intersect_line_plane line4, plane
      p5 = Geom.intersect_line_plane line5, plane
      p6 = Geom.intersect_line_plane line6, plane
      p7 = Geom.intersect_line_plane line7, plane
      p8 = Geom.intersect_line_plane line8, plane
      p9 = Geom.intersect_line_plane line9, plane
      p10 = Geom.intersect_line_plane line10, plane
      p11 = Geom.intersect_line_plane line11, plane
      p12 = Geom.intersect_line_plane line12, plane
      if p1 ### NOT z
        e1 = newgroupentities.add_line p1,p2
        e2 = newgroupentities.add_line p2,p3
        e3 = newgroupentities.add_line p3,p4
        e4 = newgroupentities.add_line p4,p1
      elsif  p5 ### in z
        e1 = newgroupentities.add_line p5,p6
        e2 = newgroupentities.add_line p6,p8
        e3 = newgroupentities.add_line p8,p7
        e4 = newgroupentities.add_line p7,p5
      else
        e1 = newgroupentities.add_line p9,p10
        e2 = newgroupentities.add_line p10,p11
        e3 = newgroupentities.add_line p11,p12
        e4 = newgroupentities.add_line p12,p9
      end #if p1 etc
      face = newgroupentities.add_face [e1,e2,e3,e4]
      newgroup
    end

    def delete_model_behind_plane(first,t1,plane)
      ents=get_entities(first)
      ents.each {|e|
        if e.visible?
          if e.class==Sketchup::Group or e.class==Sketchup::ComponentInstance
            Sketchup.set_status_text("Deleting entities behind plane for #{get_entities(e).parent.name}...")
            delete_model_behind_plane(e,t1*e.transformation,plane)
          end
        end
      }
      delete_ents_behind_plane(first,t1,plane)
    end

    def delete_ents_behind_plane(first,t1,plane)
      ents=get_entities(first)
      delete=[]
      ents.each {|e|
        if e.class==Sketchup::Face
          mesh=e.mesh
          mesh.transform!(t1)  #transform face to global coordinates
          p1=mesh.point_at(1)
          p2=mesh.point_at(2)
          p3=mesh.point_at(3)
          cent=[(p1.x+p2.x+p3.x)/3.0,(p1.y+p2.y+p3.y)/3.0,(p1.z+p2.z+p3.z)/3.0]
          result=plane[0]*cent.x+plane[1]*cent.y+plane[2]*cent.z+plane[3]
          delete.push(e) if result<0.0
        elsif e.class==Sketchup::Edge
          p1=e.start.position
          p2=e.end.position
          p1=p1.transform(t1)
          p2=p2.transform(t1)
          cent=[(p1.x+p2.x)/2.0,(p1.y+p2.y)/2.0,(p1.z+p2.z)/2.0]
          result=plane[0]*cent.x+plane[1]*cent.y+plane[2]*cent.z+plane[3]
          delete.push(e) if result<0.0 and cent.distance_to_plane(plane)>0.001
          #delete.push(e) if cent.distance_to_plane(plane)>0.1
        end
      }

      ents.erase_entities(delete)  #delete the entities behind tha plane
    end

    def make_unique_section_cut(ents,t1,plane)
      delete=[]
      ents.each {|e|
        if e.visible?
          if e.class==Sketchup::Group or e.class==Sketchup::ComponentInstance
            res=bounds_intersects_plane?(e,t1,plane)
            if res==0  #intersects plane
              e.make_unique
              make_unique_section_cut(get_entities(e),t1*e.transformation,plane)
            elsif res==-1  #behind plane
              delete.push(e)
            end
          end
        end
      }

      ents.erase_entities(delete)
    end

    def make_unique_zorro_cut(ents,t1,plane)
      ents.each {|e|
        if e.visible?
          if e.class==Sketchup::Group or e.class==Sketchup::ComponentInstance
            res=bounds_intersects_plane?(e,t1,plane)
            if res==0  #intersects plane
              e.make_unique
              make_unique_zorro_cut(get_entities(e),t1*e.transformation,plane)
            end
          end
        end
      }
    end

    def slice_model_at_section(section)
      plane=section.get_plane
      model=Sketchup.active_model
      if Sketchup.version[0,1].to_i >= 7
        model.start_operation("Slice at Section",true)
      else
        model.start_operation("Slice at Section")
      end

      ents=Sketchup.active_model.active_entities
      Sketchup.set_status_text("Making unique components and deleting groups and components behind section plane...")
      make_unique_section_cut(ents,Geom::Transformation.new,plane)
      knife_group=create_face_from_section(section)
      nested_slash(ents.parent,Geom::Transformation.new,knife_group,knife_group.transformation)
      ents.erase_entities(knife_group)
      delete_model_behind_plane(ents.parent,Geom::Transformation.new,plane)
      delete_helpers
      model.commit_operation
    end

    def get_entities(object)
      if object.class==Sketchup::Model
        return object.entities
      elsif object.class==Sketchup::Group
        return object.entities
      elsif object.class==Sketchup::ComponentInstance
        return object.definition.entities
      elsif object.class==Sketchup::ComponentDefinition
        return object.entities
      else
        return nil
      end
    end

  end #class

  def self.get_icon(name)
    ext = Sketchup.platform == :platform_osx ? '.png' : '.svg'
    File.join(File.dirname(__FILE__), 'images', name + ext)
  end

  unless file_loaded?(__FILE__)
    main_menu = UI.menu("Plugins")
    toolbar = UI::Toolbar.new(PLUGIN_NAME)
    main_menu = main_menu.add_submenu(PLUGIN_NAME)

    cmd = UI::Command.new("Zorro") { Sketchup.active_model.select_tool Zorro2Tool.new }
    cmd.tooltip = "Zorro Slice Tool"
    cmd.status_bar_text = "Create Edges by slicing through Objects"
    cmd.large_icon = cmd.small_icon = self.get_icon('sword')
    toolbar.add_item(cmd)
    main_menu.add_item(cmd)

    case toolbar.get_last_state
      when -1, 1 #never been shown or visible
        toolbar.show
      else
        toolbar.hide
    end

    UI.add_context_menu_handler {|menu|
      sel=Sketchup.active_model.selection.first
      menu.add_separator
      next unless sel
      if sel.class == Sketchup::SectionPlane
        menu.add_item("Slice Model at Section") {Zorro2Tool.new.slice_model_at_section(sel)}
      end
    }
  file_loaded(__FILE__)
  end

  PATH = File.dirname(__FILE__)
  def self.reload
    files = %w(
      zorro.rb
    )
    files.each { |f|
      load(File.join(PATH, f))
    }
  end

end #module
