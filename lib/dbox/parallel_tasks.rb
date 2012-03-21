require "thread"

#
# Usage:
#
#  puts "Creating task queue with 5 concurrent workers"
#  tasks = ParallelTasks.new(5) { puts "Worker thread starting up" }
#
#  puts "Starting workers"
#  tasks.start
#
#  puts "Making some work"
#  20.times do
#    tasks.add do
#      x = rand(5)
#      puts "Sleeping for #{x}s"
#      sleep x
#    end
#  end
#
#  puts "Waiting for workers to finish"
#  tasks.finish
#
#  puts "Done"
#
class ParallelTasks
  def initialize(num_workers, &initialization_proc)
    @num_workers = num_workers
    @initialization_proc = initialization_proc
    @workers = []
    @work_queue = Queue.new
    @semaphore = Mutex.new
    @done_making_tasks = false
  end

  def start
    @num_workers.times do
      @workers << Thread.new do
        @initialization_proc.call if @initialization_proc
        done = false
        while !done
          task = nil
          @semaphore.synchronize do
            unless @work_queue.empty?
              task = @work_queue.pop()
            else
              if @done_making_tasks
                done = true
              else
                sleep 0.1
              end
            end
          end
          if task
            begin
              task.call
            rescue Exception => e
              log.error e.inspect
            end
          end
        end
      end
    end
  end

  def add(&proc)
    @work_queue << proc
  end

  def finish
    @done_making_tasks = true
    @workers.each {|t| t.join }
  end
end
