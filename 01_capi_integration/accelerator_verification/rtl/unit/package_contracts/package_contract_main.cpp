#include "Vpackage_contract_tb.h"
#include "verilated.h"
#include "verilated_cov.h"

int main(int argc, char **argv)
{
    VerilatedContext context;
    Vpackage_contract_tb top{&context};

    context.commandArgs(argc, argv);
    while(!context.gotFinish())
    {
        top.eval();
        context.timeInc(1);
    }
    top.final();
#if VM_COVERAGE
    context.coveragep()->write("coverage.dat");
#endif
    return 0;
}
