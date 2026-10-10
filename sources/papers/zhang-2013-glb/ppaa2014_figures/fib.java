public class FibG(n:Long) {
    class FibTQ implements TaskQueue{
	val bag = new ArrayListTaskBag[Long]();
	var result:Long=0;
	public def getTaskBag()=bag;
	public def getResult()= result;
	public def init(n:Long) {
	    bag.bag().add(n);
	}
	public def process(var n:Long):Boolean {
	    val b = bag.bag();
	    for (var i:Long=0; bag.size() > 0 && i < n; i++) {
		val x = b.removeLast(); // constant time
		if (x < 2) result += x;
		else {
		    b.add(x-1); // constant time
		    b.add(x-2);
		}
	    }
	    return b.size()>0;
	}			
	public def merge(var _tb:glb.TaskBag):void {
	    this.bag.merge(_tb as ArrayListTaskBag[Long]);
	}	
	public def split():glb.TaskBag {
	    return this.bag.split();
	}	
	public def reduce():void {
	    result= Team.WORLD.allreduce(result,Team.ADD); 
	}	
    }
    public def run():Long {
	val init = ()=>{ return new FibTQ(); };
	val glb = new GLB[FibTQ](init, GLBParameters.Default, true);
	val start = ()=>{ (glb.taskQueue()).init(n); };
	glb.run(start);
	PlaceGroup.WORLD.broadcastFlat(()=>{
		(glb.taskQueue()).reduce();
	    });
	return glb.taskQueue().result;
    }
    public static def main(args:Rail[String]) {
	val N = args.size < 1 ? 10 : Long.parseLong(args(0));
	val result = new FibG(N).run();
	Console.OUT.println("fib-glb(" + N + ")" + result);
		
    }
}
