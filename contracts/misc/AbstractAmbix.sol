pragma solidity ^0.5.0;

import "openzeppelin-solidity/contracts/token/ERC20/ERC20Burnable.sol";
import "openzeppelin-solidity/contracts/token/ERC20/SafeERC20.sol";
import "openzeppelin-solidity/contracts/ownership/Ownable.sol";

/**
  @dev Ambix contract is used for morph Token set to another
  Token's by rule (recipe). In distillation process given
  Token's are burned and result generated by emission.
  
  The recipe presented as equation in form:
  (N1 * A1 & N'1 * A'1 & N''1 * A''1 ...)
  | (N2 * A2 & N'2 * A'2 & N''2 * A''2 ...) ...
  | (Nn * An & N'n * A'n & N''n * A''n ...)
  = M1 * B1 & M2 * B2 ... & Mm * Bm 
    where A, B - input and output tokens
          N, M - token value coeficients
          n, m - input / output dimetion size 
          | - is alternative operator (logical OR)
          & - is associative operator (logical AND)
  This says that `Ambix` should receive (approve) left
  part of equation and send (transfer) right part.
*/
contract AbstractAmbix is Ownable {
    using SafeERC20 for ERC20Burnable;
    using SafeERC20 for ERC20;

    address[][] public A;
    uint256[][] public N;
    address[] public B;
    uint256[] public M;

    /**
     * @dev Append token recipe source alternative
     * @param _a Token recipe source token addresses
     * @param _n Token recipe source token counts
     **/
    function appendSource(
        address[] calldata _a,
        uint256[] calldata _n
    ) external onlyOwner {
        uint256 i;

        require(_a.length == _n.length && _a.length > 0, "source token addresses and counts mismatch");

        for (i = 0; i < _a.length; ++i) require(_a[i] != address(0), "source zero address");

        if (_n.length == 1 && _n[0] == 0) {
            require(B.length == 1, "output token length mismatch");
        } else {
            for (i = 0; i < _n.length; ++i) require(_n[i] > 0, "source zero counts");
        }

        A.push(_a);
        N.push(_n);
    }

    /**
     * @dev Set sink of token recipe
     * @param _b Token recipe sink token list
     * @param _m Token recipe sink token counts
     */
    function setSink(
        address[] calldata _b,
        uint256[] calldata _m
    ) external onlyOwner {
        require(_b.length == _m.length, "sink token addresses and counts mismatch");

        for (uint256 i = 0; i < _b.length; ++i)
            require(_b[i] != address(0), "sink zero address");

        B = _b;
        M = _m;
    }

    function _run(uint256 _ix) internal {
        require(_ix < A.length, "input token lenght mismatch");
        uint256 i;

        if (N[_ix][0] > 0) {
            // Static conversion

            // Token count multiplier
            uint256 mux = ERC20(A[_ix][0]).allowance(msg.sender, address(this)) / N[_ix][0];
            require(mux > 0, "sender zero allowance");

            // Burning run
            for (i = 0; i < A[_ix].length; ++i)
                ERC20Burnable(A[_ix][i]).burnFrom(msg.sender, mux * N[_ix][i]);

            // Transfer up
            for (i = 0; i < B.length; ++i)
                ERC20(B[i]).safeTransfer(msg.sender, M[i] * mux);

        } else {
            // Dynamic conversion
            //   Let source token total supply is finite and decrease on each conversion,
            //   just convert finite supply of source to tokens on balance of ambix.
            //         dynamicRate = balance(sink) / total(source)

            // Is available for single source and single sink only
            require(A[_ix].length == 1 && B.length == 1, "Dynamic conversion is available for single source and single sink only");

            ERC20Burnable source = ERC20Burnable(A[_ix][0]);
            ERC20 sink = ERC20(B[0]);

            uint256 scale = 10 ** 18 * sink.balanceOf(address(this)) / source.totalSupply();

            uint256 allowance = source.allowance(msg.sender, address(this));
            require(allowance > 0, "sender zero allowance(2)");
            source.burnFrom(msg.sender, allowance);

            uint256 reward = scale * allowance / 10 ** 18;
            require(reward > 0, "zero reward");
            sink.safeTransfer(msg.sender, reward);
        }
    }
}
