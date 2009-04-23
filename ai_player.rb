require 'map'
require 'sprite'
require 'weapon'

module AStar
  Coordinate = Struct.new(:x, :y)
  
  def find_path(map, start, goal)
    start  = Coordinate.new(start[0], start[1])
    goal   = Coordinate.new(goal[0], goal[1])
    
    closed = []
    open   = [start]
    
    g_score = {}
    h_score = {}
    f_score = {}
    came_from = {}
    
    g_score[start] = 0
    h_score[start] = heuristic_estimate_of_distance(start, goal)
    f_score[start] = h_score[start]
    
    while not open.empty?
      x = smallest_f_score(open, f_score)
      return reconstruct_path(came_from, goal) if x == goal
      
      open.delete(x)
      closed << x
      neighbor_nodes = neighbor_nodes(map, x)
      
      neighbor_nodes.each do |y|
        next if closed.include?(y) or not map.walkable?(y.y, y.x)
        
        tentative_g_score = g_score[x] + dist_between(x, y)
        tentative_is_better = false
        if not open.include?(y)
          open << y
          h_score[y] = heuristic_estimate_of_distance(y, goal)
          tentative_is_better = true
        elsif tentative_g_score < g_score[y]
          tentative_is_better = true
        end
        
        if tentative_is_better
          came_from[y] = x
          g_score[y] = tentative_g_score
          f_score[y] = g_score[y] + h_score[y]
        end
      end
    end
    
    # No path found
    return nil
  end
  
  def dist_between(a, b)
    col_a, row_a = Map.matrixify(a.x, a.y)
    col_b, row_b = Map.matrixify(b.x, b.y)
    
    if col_a == col_b && row_a != row_b
      1.0
    elsif col_a != col_b && row_a == row_b
      1.0
    else
      1.4142135623731 # Sqrt(1**2 + 1**2)
    end
  end
  
  def neighbor_nodes(map, node)
    node_x, node_y = node.x, node.y
    result = []

    x = node_x - 1
    x_max = node_x + 1
    y_max = node_y + 1
    while(x <= x_max && x < map.width)
      y = node_y - 1
      
      while(y <= y_max && y < map.height)
        result << Coordinate.new(x, y) unless (x == node_x && y == node_y)
        y += 1
      end
      
      x += 1
    end
    
    return result
    
  end
  
  def heuristic_estimate_of_distance(start, goal)
    # Manhattan distance
    (goal.x - start.x).abs + (goal.y - start.y).abs
  end
  
  def reconstruct_path(came_from, current_node)
    #puts "START TRACE"
    
    while came_from[current_node]
      #puts "#{current_node[0]}, #{current_node[1]}"
      parent = came_from[current_node]
      
      if came_from[parent].nil?
        # No more parent for this node, return the current_node
        return current_node
      else
        current_node = parent
      end
    end
    
    #puts "No path found"
  end
  
  def smallest_f_score(list_of_coordinates, f_score)
    x_min = list_of_coordinates[0]
    f_min = f_score[x_min]
    
    list_of_coordinates.each {|x|
      if f_score[x] < f_min
        f_min = f_score[x]
        x_min = x
      end
    }
    
    return x_min
  end
  
end

class AIPlayer
  include AStar
  include Sprite
  include Damageable
  
  # Maximum distance (in blocks) that this player can see.
  attr_accessor :sight
  
  attr_accessor :steps_removed_from_player
  
  def initialize
    @sight = 10
  end
  
  def interact(player, drawn_sprite_x)
    return if @health <= 0
    
    if @firing_left > 0
      if (@current_anim_seq_id == 0)
        self.fire(player)
      end
      @firing_left -= 1
      return
    end
    
    if drawn_sprite_x.include?(self) && rand > 0.96
      @firing_left = rand(4) * 6
    end
    
    #dx = player.x - @x
    #dy = (player.y - @y) * -1
    
    #angle_rad = Math::atan2(dy, dx)
    #dx = @steps_removed_from_player * @step_size * Math::cos(angle_rad)
    #dy = @steps_removed_from_player * @step_size * Math::sin(angle_rad)
    
    #FIXME : Fix that the path should not go directly to the player, but should stop
    #        one or two blocks ahead.
    
    dx = 0
    dy = 0
    
    path = self.find_path(@map, Map.matrixify(@x, @y), Map.matrixify(player.x - dx, player.y - dy))
    if not path.nil?
      self.step_to_adjacent_squarily(path.y, path.x)
    end
  end
end

class Enemy < AIPlayer
  attr_accessor :step_size
  attr_accessor :animation_interval
  
  def initialize(window, kind_tex_paths, map, x, y, step_size = 4, animation_interval = 0.2)
    super()
    @window = window
    @x = x
    @y = y
    @slices = {}
    @health = 100
    @map = map
    @steps_removed_from_player = 22
    @firing_left = 0
    
    kind_tex_paths.each { |kind, tex_paths|
      @slices[kind] = []
      tex_paths.each { |tex_path|
        @slices[kind] << SpritePool::get(window, tex_path, TEX_HEIGHT)
      }
    }
    
    @step_size = step_size
    @animation_interval = animation_interval
    
    self.current_state = :idle
    @last_draw_time = Time.now.to_f
  end
  
  def take_damage_from(player)
    return if @current_state == :dead
    @health -= 5 # TODO: Need to refactor this to take into account different weapons.
    self.current_state = (@health > 0) ? :damaged : :dead
  end
  
  def step_to_adjacent_squarily(target_row, target_column)
    my_column, my_row = Map.matrixify(@x, @y)
    x = my_column
    y = my_row
    
    if my_column == target_column || my_row == target_row
      type = "orthogonal"
      # Orthogonal
      x = target_column # * Map::GRID_WIDTH_HEIGHT
      y = target_row    # * Map::GRID_WIDTH_HEIGHT
    else
      # Diagonal
      type = "diagonal"
      x = my_column
      y = target_row
      
      if not @map.walkable?(y, x)
        x = target_column
        y = my_row
      end
    end
    
    x += 0.5
    y += 0.5
    
    x *= Map::GRID_WIDTH_HEIGHT
    y *= Map::GRID_WIDTH_HEIGHT
    
    #puts "#{Time.now} -- (#{x}, #{y})"
    self.step_to(x, y)
    
  end
  
  def step_to(x, y)
    return if @current_state == :dead
    
    if (@x == x && @y == y)
      self.current_state = :idle
      return
    end
    
    self.current_state = :walking if self.current_state != :walking &&
      @current_anim_seq_id + 1 == @slices[@current_state].size
    
    dx = x - @x
    dy = (y - @y) * -1
    
    angle_rad = Math::atan2(dy, dx) * -1
    
    @x += @step_size * Math::cos(angle_rad)
    @y += @step_size * Math::sin(angle_rad)
  end
  
  def current_state
    @current_state
  end
  
  def current_state=(state)
    @current_state       = state
    @current_anim_seq_id = 0
    if state == :idle || state == :walking || state == :firing
      @repeating_anim = true
    else
      @repeating_anim = false
    end
  end
  
  def slices
    # Serve up current slice
    now = Time.now.to_f
    
    if not (( @current_state == :dead and @current_anim_seq_id + 1 == @slices[:dead].size ) or (@current_state == :idle))
      if now >= @last_draw_time + @animation_interval
        @current_anim_seq_id += 1
        if @repeating_anim
          @current_anim_seq_id = @current_anim_seq_id % @slices[@current_state].size
        else
          if @current_anim_seq_id >= @slices[@current_state].size
            self.current_state = :idle
          end
        end
        
        @last_draw_time = now
      end
    end
    
    return @slices[@current_state][@current_anim_seq_id]
  end
  
  def fire(player)
    return if @current_status == :dead
    
    player.take_damage_from(self)
    
    self.current_state = :firing
  end
end

class Hans < Enemy
  def initialize(window, map, x, y, step_size = 3, animation_interval = 0.2)
    sprites = {
      :idle    => ['hans1.bmp'],
      :walking => ['hans1.bmp', 'hans2.bmp', 'hans3.bmp', 'hans4.bmp'],
      :firing  => ['hans5.bmp', 'hans6.bmp', 'hans7.bmp'],
      :damaged => ['hans8.bmp', 'hans9.bmp'],
      :dead    => ['hans9.bmp', 'hans10.bmp', 'hans11.bmp']
    }
    
    super(window, sprites, map, x, y, step_size, animation_interval)
  end
end