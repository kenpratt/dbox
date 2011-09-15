require "thread"

#
# Usage:
#
#  puts "Creating task queue with 5 concurrent workers"
#  tasks = ParallelTasks.new(5)
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
  def initialize(num_workers)
    @num_workers = num_workers
    @workers = []
    @work_queue = Queue.new
    @semaphore = Mutex.new
    @done_making_tasks = false
  end

  def start
    @num_workers.times do
      @workers << Thread.new do
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
          task.call if task
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
