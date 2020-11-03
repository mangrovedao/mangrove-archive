import "./Test.sol";
import "./DexCommon.sol";

contract Foo {
  function bi(uint i) public {
    emit DexEvents.TestEvent(i);
  }
}

contract Foo_Test is Test {
  function my_test() public {
    Foo f = new Foo();
    Foo g = new Foo();
    expectFrom(address(f));
    emit DexEvents.TestEvent(2);
    expectFrom(address(g));
    emit DexEvents.TestEvent(9);
    f.bi(2);
    g.bi(9);
  }
}
